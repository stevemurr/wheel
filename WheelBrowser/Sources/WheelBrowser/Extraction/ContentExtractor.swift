import Foundation
import WebKit

@MainActor
class ContentExtractor {
    private let maxContentLength = 4000
    private let articleExtractionService: ArticleExtractionService

    init(articleExtractionService: ArticleExtractionService = ArticleExtractionService()) {
        self.articleExtractionService = articleExtractionService
    }

    func extractContent(from tab: Tab) async -> PageContext? {
        guard tab.url != nil else { return nil }
        do {
            guard let article = try await articleExtractionService.extract(from: tab.webView) else {
                return nil
            }

            return pageContext(from: article)
        } catch {
            Log.Browser.error("Content extraction error", error: error)
            return nil
        }
    }

    func extractContent(from html: String, url: URL?, title: String?) async -> PageContext? {
        do {
            guard let article = try await articleExtractionService.extract(from: html, url: url, title: title) else {
                return nil
            }

            return pageContext(from: article)
        } catch {
            Log.Browser.error("Content extraction error", error: error)
            return nil
        }
    }

    private func truncateContent(_ content: String) -> String {
        guard content.count > maxContentLength else {
            return content
        }

        // Try to truncate at a sentence boundary
        let truncated = String(content.prefix(maxContentLength))

        // Find the last period followed by a space or end of string
        if let lastSentenceEnd = truncated.range(of: ". ", options: .backwards) {
            return String(truncated[..<lastSentenceEnd.upperBound]) + "..."
        }

        // Fall back to word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }

        return truncated + "..."
    }

    private func pageContext(from article: ArticleExtractionResult) -> PageContext {
        PageContext(
            url: article.url?.absoluteString ?? "about:blank",
            title: article.title,
            textContent: truncateContent(article.textContent)
        )
    }
}
