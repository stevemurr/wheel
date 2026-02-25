import Foundation

/// Service for generating AI summaries of web pages using the configured LLM endpoint
actor SummaryGenerator {
    static let shared = SummaryGenerator()

    private let maxSummaryLength = 500  // Generous limit, rely on prompt to enforce length
    private var isBackfilling = false

    private init() {}

    // MARK: - Summary Generation (Streaming)

    /// Generate a summary with streaming output
    /// Yields partial content as it arrives from the LLM
    func generateSummaryStream(content: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let settings = await MainActor.run { AppSettings.shared }

                    // Use dedicated summarization endpoint
                    guard let baseURL = await MainActor.run(body: { settings.summarizationBaseURL }) else {
                        continuation.finish(throwing: SummaryError.invalidEndpoint)
                        return
                    }

                    let chatEndpoint = baseURL.appendingPathComponent("chat/completions")
                    let model = await MainActor.run { settings.summarizationModel }

                    let truncatedContent = String(content.prefix(3000))

                    let requestBody: [String: Any] = [
                        "model": model,
                        "messages": [
                            ["role": "system", "content": "You are a concise summarizer. Provide brief, clear summaries in 2-3 sentences. Keep summaries under 100 words."],
                            ["role": "user", "content": "Summarize the following text:\n\n\(truncatedContent)"]
                        ],
                        "max_tokens": 256,
                        "temperature": 0.3,
                        "stream": true
                    ]

                    guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
                        continuation.finish(throwing: SummaryError.serializationFailed)
                        return
                    }

                    var request = URLRequest(url: chatEndpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = jsonData
                    request.timeoutInterval = 30

                    // Add Authorization header if API key is configured
                    let apiKey = await MainActor.run { settings.llmAPIKey }
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    Log.Services.info("Starting streaming request to: \(chatEndpoint)")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        Log.Services.error("HTTP error: \(statusCode)")
                        continuation.finish(throwing: SummaryError.httpError(statusCode))
                        return
                    }

                    Log.Services.debug("Got response, reading stream...")

                    for try await line in bytes.lines {
                        // Skip empty lines
                        guard !line.isEmpty else { continue }

                        Log.Services.debug("Raw line: \(line.prefix(100))")

                        var jsonString = line

                        // Handle OpenAI SSE format: "data: {...}" or "data: [DONE]"
                        if line.hasPrefix("data: ") {
                            jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                Log.Services.debug("Got [DONE]")
                                break
                            }
                        }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            Log.Services.warning("Failed to parse JSON")
                            continue
                        }

                        // Try OpenAI format: choices[0].delta.content
                        if let choices = json["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let delta = firstChoice["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            Log.Services.debug("OpenAI chunk: \(content)")
                            continuation.yield(content)
                            continue
                        }

                        // Try Ollama format: message.content (with done flag)
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            Log.Services.debug("Ollama chunk: \(content)")
                            continuation.yield(content)
                            // Check if done
                            if let done = json["done"] as? Bool, done {
                                Log.Services.debug("Ollama done flag received")
                                break
                            }
                            continue
                        }
                    }

                    Log.Services.info("Stream finished successfully")
                    continuation.finish()

                } catch {
                    Log.Services.error("Stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    enum SummaryError: Error {
        case invalidEndpoint
        case serializationFailed
        case httpError(Int)
    }

    // MARK: - Summary Generation (Non-streaming)

    /// Generate a summary for the given content
    /// Returns nil on failure (network error, invalid response, etc.)
    func generateSummary(content: String) async -> String? {
        let settings = await MainActor.run { AppSettings.shared }

        // Use dedicated summarization endpoint
        guard let baseURL = await MainActor.run(body: { settings.summarizationBaseURL }) else {
            Log.Services.error("Invalid summarization endpoint URL")
            return nil
        }

        let chatEndpoint = baseURL.appendingPathComponent("chat/completions")
        let model = await MainActor.run { settings.summarizationModel }

        // Truncate content to avoid overwhelming the LLM
        let truncatedContent = String(content.prefix(3000))

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a concise summarizer. Provide brief, clear summaries in 2-3 sentences. Keep summaries under 100 words."],
                ["role": "user", "content": "Summarize the following text:\n\n\(truncatedContent)"]
            ],
            "max_tokens": 256,
            "temperature": 0.3
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            Log.Services.error("Failed to serialize request")
            return nil
        }

        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        // Add Authorization header if API key is configured
        let apiKey = await MainActor.run { settings.llmAPIKey }
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                Log.Services.error("HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.Services.error("Failed to parse JSON response")
                if let responseStr = String(data: data, encoding: .utf8) {
                    Log.Services.debug("Raw response: \(responseStr.prefix(500))")
                }
                return nil
            }

            // Try OpenAI-compatible format first (choices[0].message.content)
            if let choices = json["choices"] as? [Any],
               let firstChoice = choices.first as? [String: Any],
               let messageAny = firstChoice["message"] {

                // Convert to NSDictionary for reliable access
                guard let message = messageAny as? NSDictionary else {
                    Log.Services.warning("Could not convert message to dictionary")
                    return nil
                }

                // Try content field first (check it's not NSNull)
                if let content = message["content"] as? String, !content.isEmpty {
                    Log.Services.debug("Raw response: \(content.prefix(300))")
                    if let cleaned = cleanSummaryResponse(content) {
                        return String(cleaned.prefix(maxSummaryLength))
                    }
                }

                // For reasoning models: extract from reasoning_content
                if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
                    // The reasoning often contains the summary - try to extract it
                    // Look for quoted text or the last complete sentence
                    if let extracted = extractSummaryFromReasoning(reasoning) {
                        return String(extracted.prefix(maxSummaryLength))
                    }
                }
            }

            // Try Ollama native format (message.content)
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                if let cleaned = cleanSummaryResponse(content) {
                    return String(cleaned.prefix(maxSummaryLength))
                }
            }

            // Try direct response format (response)
            if let content = json["response"] as? String {
                if let cleaned = cleanSummaryResponse(content) {
                    return String(cleaned.prefix(maxSummaryLength))
                }
            }

            Log.Services.warning("Unexpected response format. Keys: \(json.keys.joined(separator: ", "))")
            return nil

        } catch {
            Log.Services.error("Network error: \(error.localizedDescription)")
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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

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

    /// Extract a summary from reasoning model output
    /// Reasoning models often include the summary in quotes or after certain phrases
    private func extractSummaryFromReasoning(_ reasoning: String) -> String? {
        // Try to find quoted text (the summary is often in quotes)
        let quotePattern = "\"([^\"]{20,})\""
        if let regex = try? NSRegularExpression(pattern: quotePattern),
           let match = regex.firstMatch(in: reasoning, range: NSRange(reasoning.startIndex..., in: reasoning)),
           let range = Range(match.range(at: 1), in: reasoning) {
            let extracted = String(reasoning[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if extracted.count >= 20 {
                return extracted
            }
        }

        // Try to find text after "like:" or "summary:"
        let prefixes = ["like:", "summary:", "produce:"]
        for prefix in prefixes {
            if let range = reasoning.range(of: prefix, options: .caseInsensitive) {
                let afterPrefix = reasoning[range.upperBound...]
                // Take up to the next sentence end or max characters
                let cleaned = String(afterPrefix)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")

                // Find first sentence
                if let sentenceEnd = cleaned.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                    let sentence = String(cleaned[...sentenceEnd])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if sentence.count >= 20 {
                        return sentence
                    }
                }
            }
        }

        // Fallback: take first substantial sentence from reasoning
        let sentences = reasoning.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for sentence in sentences {
            let cleaned = sentence
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            // Skip meta-sentences about the task
            if cleaned.count >= 30 &&
               !cleaned.lowercased().contains("we need") &&
               !cleaned.lowercased().contains("let's") &&
               !cleaned.lowercased().contains("characters") &&
               !cleaned.lowercased().contains("summarize") {
                return cleaned
            }
        }

        return nil
    }
}
