import SwiftUI
import Combine

@MainActor
class LinkPreviewState: ObservableObject {
    static let shared = LinkPreviewState()

    @Published var isVisible: Bool = false
    @Published var position: CGPoint = .zero
    @Published var linkURL: URL?
    @Published var linkText: String = ""
    @Published var pageTitle: String?
    @Published var summary: String?
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    private init() {}

    func requestPreview(url: URL, linkText: String, position: CGPoint) {
        // Check if link previews are enabled
        guard AppSettings.shared.linkPreviewEnabled else { return }

        // Cancel any pending debounce
        debounceTask?.cancel()

        // Debounce - wait 300ms before showing preview
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            // Show preview
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
    }

    func hide() {
        debounceTask?.cancel()
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
        fetchTask?.cancel()

        fetchTask = Task {
            do {
                // Fetch page content
                let (title, content) = try await fetchPageTitleAndContent(url: url)

                guard !Task.isCancelled else { return }

                self.pageTitle = title

                // Generate summary using existing SummaryGenerator with streaming
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

                    // Stream summary content as it arrives
                    self.summary = ""
                    let stream = await SummaryGenerator.shared.generateSummaryStream(content: content)

                    do {
                        for try await chunk in stream {
                            guard !Task.isCancelled else { return }
                            self.summary = (self.summary ?? "") + chunk
                        }

                        // Clean up the final summary
                        if let finalSummary = self.summary, !finalSummary.isEmpty {
                            // Trim and limit length
                            self.summary = String(finalSummary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
                        }
                    } catch {
                        // Streaming failed, try fallback to content snippet
                        if self.summary?.isEmpty ?? true {
                            self.summary = String(content.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
                        }
                    }
                }

                self.isLoading = false

            } catch {
                guard !Task.isCancelled else { return }

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

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        let title = extractTitle(from: html)
        let content = extractContent(from: html)

        return (title, content)
    }

    private func extractTitle(from html: String) -> String? {
        // Try og:title first
        if let ogTitle = extractMetaContent(html: html, property: "og:title") {
            return ogTitle
        }

        // Fall back to <title> tag
        let titlePattern = "<title[^>]*>([^<]+)</title>"
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func extractMetaContent(html: String, property: String) -> String? {
        let pattern = "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"']([^\"']+)[\"']"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // Try reversed order (content before property)
        let patternAlt = "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*property=[\"']\(property)[\"']"
        if let regex = try? NSRegularExpression(pattern: patternAlt, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        return nil
    }

    private func extractContent(from html: String) -> String? {
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
}
