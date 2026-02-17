import Foundation
import WebKit

@MainActor
class ContentExtractor {
    private let maxContentLength = 4000

    private let extractionScript = """
    (function() {
        // Remove script, style, and other non-content elements
        const removeSelectors = [
            'script', 'style', 'noscript', 'iframe', 'svg',
            'nav', 'header', 'footer', 'aside',
            '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
            '.sidebar', '.nav', '.menu', '.advertisement', '.ad'
        ];

        // Clone the document to avoid modifying the original
        const doc = document.cloneNode(true);

        // Remove unwanted elements
        removeSelectors.forEach(selector => {
            doc.querySelectorAll(selector).forEach(el => el.remove());
        });

        // Try to find main content
        const mainContent = doc.querySelector('main, article, [role="main"], .content, .post, .article');
        const contentElement = mainContent || doc.body;

        // Extract text content
        let text = contentElement ? contentElement.innerText : document.body.innerText;

        // Clean up whitespace
        text = text
            .replace(/\\s+/g, ' ')
            .replace(/\\n\\s*\\n/g, '\\n')
            .trim();

        return {
            title: document.title,
            url: window.location.href,
            text: text
        };
    })();
    """

    func extractContent(from tab: Tab) async -> PageContext? {
        guard tab.url != nil else { return nil }

        return await withCheckedContinuation { continuation in
            tab.webView.evaluateJavaScript(extractionScript) { result, error in
                if let error = error {
                    print("Content extraction error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let dict = result as? [String: Any],
                      let title = dict["title"] as? String,
                      let url = dict["url"] as? String,
                      let text = dict["text"] as? String else {
                    continuation.resume(returning: nil)
                    return
                }

                // Truncate content to fit within LLM context limits
                let truncatedText = self.truncateContent(text)

                continuation.resume(returning: PageContext(
                    url: url,
                    title: title,
                    textContent: truncatedText
                ))
            }
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
            return String(truncated[..<lastSentenceEnd.upperBound])
        }

        // Fall back to word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }

        return truncated + "..."
    }

    func extractMetadata(from tab: Tab) async -> PageMetadata? {
        let metadataScript = """
        (function() {
            const getMeta = (name) => {
                const el = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
                return el ? el.getAttribute('content') : null;
            };

            return {
                title: document.title,
                description: getMeta('description') || getMeta('og:description'),
                author: getMeta('author'),
                keywords: getMeta('keywords'),
                ogTitle: getMeta('og:title'),
                ogImage: getMeta('og:image'),
                canonical: document.querySelector('link[rel="canonical"]')?.href
            };
        })();
        """

        return await withCheckedContinuation { continuation in
            tab.webView.evaluateJavaScript(metadataScript) { result, error in
                if let error = error {
                    print("Metadata extraction error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let dict = result as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: PageMetadata(
                    title: dict["title"] as? String ?? "",
                    description: dict["description"] as? String,
                    author: dict["author"] as? String,
                    keywords: dict["keywords"] as? String,
                    ogTitle: dict["ogTitle"] as? String,
                    ogImage: dict["ogImage"] as? String,
                    canonical: dict["canonical"] as? String
                ))
            }
        }
    }
}

struct PageMetadata {
    let title: String
    let description: String?
    let author: String?
    let keywords: String?
    let ogTitle: String?
    let ogImage: String?
    let canonical: String?
}
