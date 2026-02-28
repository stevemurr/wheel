import SwiftUI
import Combine

@MainActor
class LinkPreviewState: ObservableObject {
    static let shared = LinkPreviewState()

    // MARK: - Cached Regexes (compiled once)

    private static let titleRegex = try? NSRegularExpression(
        pattern: "<title[^>]*>([^<]+)</title>",
        options: .caseInsensitive
    )
    private static let metaPropertyRegex = try? NSRegularExpression(
        pattern: "<meta[^>]*property=[\"']og:title[\"'][^>]*content=[\"']([^\"']+)[\"']",
        options: .caseInsensitive
    )
    private static let metaPropertyAltRegex = try? NSRegularExpression(
        pattern: "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*property=[\"']og:title[\"']",
        options: .caseInsensitive
    )
    private static let scriptRegex = try? NSRegularExpression(
        pattern: "<script[^>]*>[\\s\\S]*?</script>",
        options: []
    )
    private static let styleRegex = try? NSRegularExpression(
        pattern: "<style[^>]*>[\\s\\S]*?</style>",
        options: []
    )
    private static let tagRegex = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )
    private static let whitespaceRegex = try? NSRegularExpression(
        pattern: "\\s+",
        options: []
    )

    @Published var isVisible: Bool = false
    @Published var position: CGPoint = .zero
    @Published var linkURL: URL?
    @Published var linkText: String = ""
    @Published var pageTitle: String?
    @Published var summary: String?
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var fetchTask: Task<Void, Never>?

    private init() {}

    /// Shows a summary window immediately (triggered by Option+Click)
    func showSummary(url: URL, linkText: String, position: CGPoint) {
        // Check if link previews are enabled
        guard AppSettings.shared.linkPreviewEnabled else {
            return
        }

        // If already showing for a different URL, dismiss first
        if isVisible && linkURL != url {
            fetchTask?.cancel()
        }

        Log.LinkPreview.info("Summary: \(url.host ?? url.absoluteString)")

        // Show summary window immediately (no debounce for click-based trigger)
        self.linkURL = url
        self.linkText = linkText
        self.position = position
        self.pageTitle = nil
        self.summary = nil
        self.error = nil
        self.isLoading = true

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            self.isVisible = true
        }

        // Start fetching content
        self.fetchPreviewContent(for: url)
    }

    /// Dismisses the summary window (user clicked close button)
    func dismiss() {
        fetchTask?.cancel()

        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = false
        }

        // Reset state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.linkURL = nil
            self.linkText = ""
            self.pageTitle = nil
            self.summary = nil
            self.error = nil
            self.isLoading = false
        }
    }

    private func fetchPreviewContent(for url: URL) {
        if fetchTask != nil {
            Log.LinkPreview.debug("Cancelling previous fetch")
        }
        fetchTask?.cancel()

        fetchTask = Task {
            // Check LLM configuration before starting
            let settings = AppSettings.shared
            guard let llmURL = settings.summarizationBaseURL else {
                Log.LinkPreview.error("LLM endpoint not configured (llmEndpoint='\(settings.llmEndpoint)')")
                self.error = "LLM not configured"
                self.isLoading = false
                return
            }
            Log.LinkPreview.debug("Using LLM at \(llmURL.absoluteString)")

            do {
                // Fetch page content
                let (title, content) = try await fetchPageTitleAndContent(url: url)

                guard !Task.isCancelled else {
                    Log.LinkPreview.debug("Request cancelled after fetch")
                    return
                }

                Log.LinkPreview.debug("Fetched '\(title ?? "no title")' (\(content?.count ?? 0) chars)")
                self.pageTitle = title

                // Generate summary using SummaryGenerator
                if let content = content, !content.isEmpty {
                    // Index page in DIndex since we're fetching it anyway
                    // This runs in background and doesn't block the preview
                    if AppSettings.shared.dindexEnabled {
                        Task.detached {
                            await SemanticSearchManagerV2.shared.indexPage(
                                url: url.absoluteString,
                                title: title ?? url.host ?? "Untitled",
                                content: content,
                                workspaceID: await MainActor.run { WorkspaceManager.shared.currentWorkspaceID }
                            )
                        }
                    }

                    // Try streaming first, fall back to non-streaming if it fails
                    var streamingSucceeded = false
                    self.summary = ""

                    do {
                        Log.LinkPreview.debug("Starting streaming summary...")
                        let stream = await SummaryGenerator.shared.generateSummaryStream(content: content)

                        for try await chunk in stream {
                            guard !Task.isCancelled else {
                                Log.LinkPreview.debug("Request cancelled during streaming")
                                return
                            }
                            self.summary = (self.summary ?? "") + chunk
                            streamingSucceeded = true
                        }

                        // Clean up the final summary (trim whitespace only, no truncation)
                        if let finalSummary = self.summary, !finalSummary.isEmpty {
                            self.summary = finalSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                            Log.LinkPreview.info("Summary complete (\(finalSummary.count) chars)")
                        } else {
                            Log.LinkPreview.warning("Streaming returned empty summary")
                        }
                    } catch {
                        Log.LinkPreview.warning("Streaming failed: \(error.localizedDescription)")
                        streamingSucceeded = false
                    }

                    // Fall back to non-streaming if streaming didn't work
                    if !streamingSucceeded || (self.summary?.isEmpty ?? true) {
                        guard !Task.isCancelled else { return }

                        Log.LinkPreview.debug("Falling back to non-streaming...")
                        if let summary = await SummaryGenerator.shared.generateSummary(content: content) {
                            self.summary = summary
                            Log.LinkPreview.info("Non-streaming summary complete")
                        } else {
                            Log.LinkPreview.warning("All summary methods failed, using snippet")
                            self.summary = String(content.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } else {
                    Log.LinkPreview.warning("No content to summarize")
                }

                self.isLoading = false

            } catch {
                guard !Task.isCancelled else { return }

                Log.LinkPreview.error("Fetch failed: \(error.localizedDescription)")
                self.error = "Could not load preview"
                self.isLoading = false
            }
        }
    }

    private func fetchPageTitleAndContent(url: URL) async throws -> (title: String?, content: String?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        let _ = try response.asValidHTTPResponse()
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        let title = extractTitle(from: html)
        let content = extractContent(from: html)

        return (title, content)
    }

    private func extractTitle(from html: String) -> String? {
        // Try og:title first
        if let ogTitle = extractOgTitle(from: html) {
            return ogTitle
        }

        // Fall back to <title> tag
        if let regex = Self.titleRegex,
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func extractOgTitle(from html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)

        // Try property before content
        if let regex = Self.metaPropertyRegex,
           let match = regex.firstMatch(in: html, range: range),
           let captureRange = Range(match.range(at: 1), in: html) {
            return String(html[captureRange])
        }

        // Try content before property
        if let regex = Self.metaPropertyAltRegex,
           let match = regex.firstMatch(in: html, range: range),
           let captureRange = Range(match.range(at: 1), in: html) {
            return String(html[captureRange])
        }

        return nil
    }

    private func extractContent(from html: String) -> String? {
        var text = html

        // Remove script and style content using cached regexes
        if let scriptRegex = Self.scriptRegex {
            text = scriptRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let styleRegex = Self.styleRegex {
            text = styleRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // Remove HTML tags
        if let tagRegex = Self.tagRegex {
            text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        if let whitespaceRegex = Self.whitespaceRegex {
            text = whitespaceRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
