import Foundation

/// Service for generating AI summaries of web pages using the on-device LLM
actor SummaryGenerator {
    static let shared = SummaryGenerator()

    private let maxSummaryLength = 500  // Generous limit, rely on prompt to enforce length
    private var isBackfilling = false
    private let contextService: any WheelModelContextServing
    private let repository: any SummaryRepository
    private let contentFetcher: any PageContentFetching

    private static let instructions = "You are a concise summarizer. Provide brief, clear summaries in 2-3 sentences. Keep summaries under 100 words."

    init(
        contextService: any WheelModelContextServing = WheelModelContextService.shared,
        repository: (any SummaryRepository)? = nil,
        contentFetcher: any PageContentFetching = URLSessionPageContentFetcher()
    ) {
        self.contextService = contextService
        self.repository = repository ?? PageIndexStore.shared
        self.contentFetcher = contentFetcher
    }

    // MARK: - Summary Generation (Streaming)

    /// Generate a summary with streaming output
    /// Yields partial content as it arrives from the on-device LLM
    func generateSummaryStream(content: String) -> AsyncThrowingStream<String, Error> {
        let truncatedContent = String(content.prefix(3000))
        let prompt = "Summarize the following text:\n\n\(truncatedContent)"
        let requestID = UUID()
        let sessionID = WheelModelContextService.summarySessionID(for: requestID)
        let contextService = self.contextService

        Log.Services.info("Starting LMCK streaming summary generation")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var previousSummary = ""
                    let stream = try await contextService.streamSummary(
                        requestID: requestID,
                        prompt: prompt,
                        instructions: Self.instructions
                    )

                    for try await event in stream {
                        switch event {
                        case .partial(let currentSummary):
                            guard currentSummary.count > previousSummary.count else {
                                continue
                            }
                            let delta = String(currentSummary.dropFirst(previousSummary.count))
                            continuation.yield(delta)
                            previousSummary = currentSummary
                        case .completed(let response):
                            let currentSummary = response.value.summary
                            if currentSummary.count > previousSummary.count {
                                continuation.yield(String(currentSummary.dropFirst(previousSummary.count)))
                            }
                            previousSummary = currentSummary
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                try? await contextService.resetSession(sessionID: sessionID)
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    try? await contextService.resetSession(sessionID: sessionID)
                }
            }
        }
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
        let requestID = UUID()
        let sessionID = WheelModelContextService.summarySessionID(for: requestID)
        defer {
            Task {
                try? await contextService.resetSession(sessionID: sessionID)
            }
        }

        do {
            let result = try await contextService.generateSummary(
                requestID: requestID,
                prompt: prompt,
                instructions: Self.instructions
            )

            let summary = result.value.summary
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            guard summary.count >= 10 else {
                Log.Services.warning("Structured summary too short")
                return nil
            }

            return String(summary.prefix(maxSummaryLength))

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

        guard let content = await contentFetcher.fetchPageContent(url: url) else {
            Log.Services.warning("Could not fetch content for: \(url)")
            return nil
        }

        guard let summary = await generateSummary(content: content) else {
            Log.Services.warning("Could not generate summary for: \(url)")
            return nil
        }

        do {
            try await repository.initialize()
            try await repository.updateSummary(url: url.absoluteString, summary: summary)
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
            try await repository.initialize()

            // Clear all existing summaries
            try await repository.clearAllSummaries()

            let allPages = try await repository.getSavedPages(limit: 100)

            guard !allPages.isEmpty else {
                Log.Services.info("No pages to regenerate")
                return
            }

            Log.Services.info("Regenerating \(allPages.count) summaries")

            let runner = SummaryBatchRunner(
                repository: repository,
                contentFetcher: contentFetcher,
                summaryGenerator: self
            )
            await runner.run(
                pages: allPages,
                delay: .milliseconds(300),
                progressHandler: progressHandler,
                logPrefix: "Regenerated"
            )

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
            try await repository.initialize()

            let pagesWithoutSummary = try await repository.getSavedPagesWithoutSummary(limit: 20)

            guard !pagesWithoutSummary.isEmpty else {
                Log.Services.info("No pages need summaries")
                return
            }

            Log.Services.info("Found \(pagesWithoutSummary.count) pages without summaries")

            let runner = SummaryBatchRunner(
                repository: repository,
                contentFetcher: contentFetcher,
                summaryGenerator: self
            )
            await runner.run(
                pages: pagesWithoutSummary,
                delay: .milliseconds(500),
                logPrefix: "Generated summary for"
            )

            Log.Services.info("Backfill complete")

        } catch {
            Log.Services.error("Backfill error: \(error)")
        }
    }
}

extension SummaryGenerator: SummaryGenerating {}
