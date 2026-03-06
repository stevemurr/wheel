import Foundation
import WebKit

/// Handles semantic search indexing of web pages.
///
/// Extracts page content via JavaScript evaluation and sends it to
/// `SemanticSearchManagerV2` for local embedding and storage.
enum SemanticIndexingHandler {

    /// URL prefixes that should be skipped for indexing.
    private static let skipPrefixes = ["about:", "data:", "javascript:", "blob:", "chrome:", "file:"]

    /// JavaScript that extracts the main text content from a web page,
    /// stripping navigation, ads, and other non-content elements.
    private static let extractionScript = """
    (function() {
        const removeSelectors = [
            'script', 'style', 'noscript', 'iframe', 'svg',
            'nav', 'header', 'footer', 'aside',
            '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
            '.sidebar', '.nav', '.menu', '.advertisement', '.ad',
            '.cookie-banner', '.popup', '.modal', '[aria-hidden="true"]'
        ];
        const doc = document.cloneNode(true);
        removeSelectors.forEach(selector => {
            doc.querySelectorAll(selector).forEach(el => el.remove());
        });
        const mainContent = doc.querySelector('main, article, [role="main"], .content, .post, .article');
        const contentElement = mainContent || doc.body;
        let text = contentElement ? contentElement.innerText : document.body.innerText;
        text = text.replace(/\\s+/g, ' ').replace(/\\n\\s*\\n/g, '\\n').trim();
        return text;
    })();
    """

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

        // Extract content via JavaScript
        Log.Search.debug("indexPageForSemanticSearch: extracting content via JavaScript")
        webView.evaluateJavaScript(extractionScript) { result, error in
            if let error = error {
                Log.Search.debug("Content extraction failed for \(urlString): \(error.localizedDescription)")
                return
            }
            guard let content = result as? String, !content.isEmpty else {
                Log.Search.debug("Content extraction returned empty for \(urlString)")
                return
            }

            Log.Search.debug("Content extracted successfully: \(content.count) chars for \(urlString)")

            Task { @MainActor in
                await SemanticSearchManagerV2.shared.indexPage(
                    url: urlString,
                    title: title,
                    content: content,
                    workspaceID: workspaceID
                )
            }
        }
    }
}
