import Foundation
import WebKit

/// Handles semantic search indexing of web pages.
///
/// Extracts page content via JavaScript evaluation and sends it to
/// `SemanticSearchManagerV2` for local embedding and storage.
enum SemanticIndexingHandler {
    private static let articleExtractionService = ArticleExtractionService()
    private static let minimumFastPathLength = 280

    /// URL prefixes that should be skipped for indexing.
    private static let skipPrefixes = ["about:", "data:", "javascript:", "blob:", "chrome:", "file:"]

    /// Index a page for semantic search. Skips non-indexable URLs and PDFs
    /// (PDFs are registered without content extraction).
    static func indexPage(webView: WKWebView, url: URL, title: String, workspaceID: UUID?) {
        let urlString = url.absoluteString
        Log.Search.debug("indexPageForSemanticSearch called: url=\(urlString), title=\(title)")

        // Check if semantic search is enabled
        guard AppSettings.shared.semanticSearchEnabled else {
            Log.Search.debug("indexPageForSemanticSearch skipped: semantic search disabled")
            return
        }

        // Skip certain URLs
        for prefix in skipPrefixes {
            if urlString.hasPrefix(prefix) {
                Log.Search.debug("indexPageForSemanticSearch skipped: URL has prefix '\(prefix)'")
                return
            }
        }

        // Check if this is a PDF - we can't extract content via JavaScript
        // but we still want to register it so it can be saved to reading list
        let isPDF = url.pathExtension.lowercased() == "pdf" ||
                    urlString.lowercased().contains(".pdf")

        if isPDF {
            Log.Search.debug("indexPageForSemanticSearch: PDF detected, registering without content")
            Task { @MainActor in
                await SemanticSearchManagerV2.shared.registerPage(
                    url: urlString,
                    title: title,
                    workspaceID: workspaceID
                )
            }
            return
        }

        Task { @MainActor in
            guard let content = await extractIndexableContent(from: webView, url: url, title: title) else {
                Log.Search.debug("Content extraction returned empty for \(urlString)")
                return
            }

            Log.Search.debug("Content extracted successfully: \(content.count) chars for \(urlString)")

            await SemanticSearchManagerV2.shared.indexPage(
                url: urlString,
                title: title,
                content: content,
                workspaceID: workspaceID
            )
        }
    }

    @MainActor
    static func extractIndexableContent(from webView: WKWebView, url: URL, title: String) async -> String? {
        do {
            if let fastContent = try await fastPageText(from: webView),
               let normalized = normalizedIndexableContent(from: fastContent),
               normalized.count >= minimumFastPathLength {
                return normalized
            }

            let article = try await articleExtractionService.extract(from: webView)
            return normalizedIndexableContent(from: article)
        } catch {
            Log.Search.debug("Content extraction failed for \(url.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }

    static func extractIndexableContent(from html: String, url: URL?, title: String) async -> String? {
        do {
            let article = try await articleExtractionService.extract(from: html, url: url, title: title)
            return normalizedIndexableContent(from: article)
        } catch {
            Log.Search.debug("Content extraction failed for \(url?.absoluteString ?? "about:blank"): \(error.localizedDescription)")
            return nil
        }
    }

    private static func normalizedIndexableContent(from article: ArticleExtractionResult?) -> String? {
        guard let text = article?.textContent.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func normalizedIndexableContent(from text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    @MainActor
    private static func fastPageText(from webView: WKWebView) async throws -> String? {
        let script = """
        (() => {
            const root =
                document.querySelector('article') ||
                document.querySelector('main') ||
                document.querySelector('[role="main"]') ||
                document.body;

            if (!root) {
                return '';
            }

            const text = root.innerText || root.textContent || '';
            return text;
        })();
        """

        return try await webView.evaluateJavaScript(script) as? String
    }
}
