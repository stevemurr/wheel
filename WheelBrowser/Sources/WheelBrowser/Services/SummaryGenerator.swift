import Foundation

/// Service for generating AI summaries of web pages using the on-device LLM
actor SummaryGenerator {
    static let shared = SummaryGenerator()

    private let maxSummaryLength = 500  // Generous limit, rely on prompt to enforce length
    private var isBackfilling = false

    private static let instructions = "You are a concise summarizer. Provide brief, clear summaries in 2-3 sentences. Keep summaries under 100 words."

    private init() {}

    // MARK: - Summary Generation (Streaming)

    /// Generate a summary with streaming output
    /// Yields partial content as it arrives from the on-device LLM
    func generateSummaryStream(content: String) -> AsyncThrowingStream<String, Error> {
        let truncatedContent = String(content.prefix(3000))
        let prompt = "Summarize the following text:\n\n\(truncatedContent)"

        Log.Services.info("Starting on-device streaming summary generation")
        return OnDeviceLLM.shared.stream(prompt: prompt, instructions: Self.instructions)
    }

    enum SummaryError: Error {
        case serializationFailed
    }

    // MARK: - Summary Generation (Non-streaming)

    /// Generate a summary for the given content
    /// Returns nil on failure (model unavailable, generation error, etc.)
    func generateSummary(content: String) async -> String? {
        let truncatedContent = String(content.prefix(3000))
        let prompt = "Summarize the following text:\n\n\(truncatedContent)"

        do {
            let result = try await OnDeviceLLM.shared.complete(prompt: prompt, instructions: Self.instructions)

            Log.Services.debug("Raw response: \(result.prefix(300))")

            if let cleaned = cleanSummaryResponse(result) {
                return String(cleaned.prefix(maxSummaryLength))
            }

            Log.Services.warning("Summary response could not be cleaned")
            return nil

        } catch {
            Log.Services.error("Summary generation error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Regeneration

    /// Regenerate summary for a specific URL
    /// Returns the new summary on success, nil on failure
    func regenerateSummary(for url: URL) async -> String? {
        Log.Services.info("Regenerating summary for: \(url)")

        guard let content = await fetchPageContent(url: url) else {
            Log.Services.warning("Could not fetch content for: \(url)")
            return nil
        }

        guard let summary = await generateSummary(content: content) else {
            Log.Services.warning("Could not generate summary for: \(url)")
            return nil
        }

        do {
            let database = SearchDatabase.shared
            try await database.initialize()
            try await database.updateSummary(url: url.absoluteString, summary: summary)
            Log.Services.info("Regenerated summary for: \(url.host ?? url.absoluteString)")
            return summary
        } catch {
            Log.Services.error("Failed to save regenerated summary: \(error)")
            return nil
        }
    }

    /// Regenerate summaries for all saved pages
    /// Clears existing summaries and regenerates them
    func regenerateAllSummaries(progressHandler: ((Int, Int) -> Void)? = nil) async {
        guard !isBackfilling else {
            Log.Services.warning("Regeneration already in progress")
            return
        }

        isBackfilling = true
        defer { isBackfilling = false }

        Log.Services.info("Starting full regeneration...")

        do {
            let database = SearchDatabase.shared
            try await database.initialize()

            // Clear all existing summaries
            try await database.clearAllSummaries()

            let allPages = try await database.getSavedPages(limit: 100)

            guard !allPages.isEmpty else {
                Log.Services.info("No pages to regenerate")
                return
            }

            Log.Services.info("Regenerating \(allPages.count) summaries")

            for (index, page) in allPages.enumerated() {
                progressHandler?(index + 1, allPages.count)

                guard let content = await fetchPageContent(url: page.url) else {
                    Log.Services.warning("Could not fetch content for: \(page.url)")
                    continue
                }

                guard let summary = await generateSummary(content: content) else {
                    Log.Services.warning("Could not generate summary for: \(page.url)")
                    continue
                }

                do {
                    try await database.updateSummary(url: page.url.absoluteString, summary: summary)
                    Log.Services.info("[\(index + 1)/\(allPages.count)] Regenerated: \(page.url.host ?? page.url.absoluteString)")
                } catch {
                    Log.Services.error("Failed to save summary: \(error)")
                }

                try? await Task.sleep(for: .milliseconds(300))
            }

            Log.Services.info("Full regeneration complete")

        } catch {
            Log.Services.error("Regeneration error: \(error)")
        }
    }

    // MARK: - Backfill

    /// Backfill summaries for saved pages that don't have one
    /// Runs in background, processing one page at a time
    func backfillSummaries() async {
        guard !isBackfilling else {
            Log.Services.warning("Backfill already in progress")
            return
        }

        isBackfilling = true
        defer { isBackfilling = false }

        Log.Services.info("Starting backfill...")

        do {
            let database = SearchDatabase.shared
            try await database.initialize()

            let pagesWithoutSummary = try await database.getSavedPagesWithoutSummary(limit: 20)

            guard !pagesWithoutSummary.isEmpty else {
                Log.Services.info("No pages need summaries")
                return
            }

            Log.Services.info("Found \(pagesWithoutSummary.count) pages without summaries")

            for page in pagesWithoutSummary {
                // Fetch page content
                guard let content = await fetchPageContent(url: page.url) else {
                    Log.Services.warning("Could not fetch content for: \(page.url)")
                    continue
                }

                // Generate summary
                guard let summary = await generateSummary(content: content) else {
                    Log.Services.warning("Could not generate summary for: \(page.url)")
                    continue
                }

                // Save summary to database
                do {
                    try await database.updateSummary(url: page.url.absoluteString, summary: summary)
                    Log.Services.info("Generated summary for: \(page.url.host ?? page.url.absoluteString)")
                } catch {
                    Log.Services.error("Failed to save summary: \(error)")
                }

                // Small delay to avoid overwhelming the LLM
                try? await Task.sleep(for: .milliseconds(500))
            }

            Log.Services.info("Backfill complete")

        } catch {
            Log.Services.error("Backfill error: \(error)")
        }
    }

    // MARK: - Content Fetching

    /// Fetch the text content of a web page
    private func fetchPageContent(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let _ = try response.asValidHTTPResponse()

            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Simple HTML to text conversion
            return extractTextFromHTML(html)

        } catch {
            return nil
        }
    }

    /// Extract readable text from HTML (simple extraction)
    private func extractTextFromHTML(_ html: String) -> String {
        var text = html

        // Remove script and style content
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"

        text = text.replacingOccurrences(of: scriptPattern, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: stylePattern, with: "", options: .regularExpression)

        // Remove HTML tags
        let tagPattern = "<[^>]+>"
        text = text.replacingOccurrences(of: tagPattern, with: " ", options: .regularExpression)

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        let whitespacePattern = "\\s+"
        text = text.replacingOccurrences(of: whitespacePattern, with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clean up a summary response, removing prompt echoes and formatting issues
    private func cleanSummaryResponse(_ raw: String) -> String? {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // If the response contains "Article:" it's echoing the prompt - extract after "Summary:"
        if text.contains("Article:") {
            if let summaryRange = text.range(of: "Summary:", options: .caseInsensitive) {
                text = String(text[summaryRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                Log.Services.warning("Response echoed prompt, no summary found")
                return nil
            }
        }

        // Remove common prefixes
        let prefixesToRemove = [
            "summary:",
            "here is the summary:",
            "here's the summary:",
            "the summary is:",
            "sure!",
            "sure,",
            "here you go:",
            "certainly!",
            "of course!",
            "okay,",
            "ok,",
        ]

        for prefix in prefixesToRemove {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Remove surrounding quotes if present
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }

        // Check for prompt contamination
        let badPatterns = ["write a", "output only", "1-2 sentence", "nothing else"]
        let lowerText = text.lowercased()
        for pattern in badPatterns {
            if lowerText.contains(pattern) {
                Log.Services.warning("Response contains prompt fragment: \(pattern)")
                return nil
            }
        }

        guard text.count >= 10 else {
            Log.Services.warning("Summary too short after cleaning: \(text)")
            return nil
        }

        return text
    }
}
