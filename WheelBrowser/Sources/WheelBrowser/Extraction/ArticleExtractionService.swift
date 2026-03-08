import Foundation
import WebKit
import Readability

struct ArticleExtractionResult {
    let title: String
    let contentHTML: String
    let textContent: String
    let excerpt: String?
    let byline: String?
    let url: URL?
}

final class ArticleExtractionService {
    @MainActor
    func extract(from webView: WKWebView) async throws -> ArticleExtractionResult? {
        guard let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String else {
            return nil
        }

        return try await extract(from: html, url: webView.url, title: webView.title)
    }

    @MainActor
    func extract(from html: String, url: URL?, title: String?) async throws -> ArticleExtractionResult? {
        let readability = Readability()
        let fallbackTitle = Self.nonEmpty(title) ?? Self.documentTitle(fromHTML: html)
        let preparedHTML = Self.prepareHTML(html, url: url, title: fallbackTitle)

        do {
            let result = try await readability.parse(
                html: preparedHTML,
                options: nil,
                baseURL: url
            )
            if let article = Self.makeReadabilityResult(
                title: result.title,
                contentHTML: result.content,
                textContent: result.textContent,
                excerpt: result.excerpt,
                byline: result.byline,
                fallbackURL: url,
                fallbackTitle: fallbackTitle
            ) {
                return article
            }
        } catch {
            Log.Browser.debug("Readability parse failed, falling back to plain text: \(error.localizedDescription)")
        }

        return Self.makeFallbackResult(from: preparedHTML, url: url, title: fallbackTitle)
    }

    private static func makeReadabilityResult(
        title: String?,
        contentHTML: String?,
        textContent: String?,
        excerpt: String?,
        byline: String?,
        fallbackURL: URL?,
        fallbackTitle: String?
    ) -> ArticleExtractionResult? {
        var normalizedText = nonEmpty(textContent).map(normalizeStructuredPlainText)
        var normalizedHTML = nonEmpty(contentHTML).map(normalizeHTML)

        if normalizedText == nil, let normalizedHTML {
            normalizedText = normalizeStructuredPlainText(plainText(fromHTML: normalizedHTML))
        }

        if normalizedHTML == nil, let normalizedText {
            normalizedHTML = wrapPlainTextAsHTML(normalizedText)
        }

        guard let finalText = nonEmpty(normalizedText),
              let finalHTML = nonEmpty(normalizedHTML) else {
            return nil
        }

        let finalTitle = preferredTitle(
            extractedTitle: title,
            fallbackTitle: fallbackTitle,
            fallbackURL: fallbackURL
        )
            ?? fallbackURL?.host
            ?? "Untitled"

        guard hasMeaningfulBodyText(
            finalText,
            titleCandidates: [finalTitle, fallbackTitle],
            fallbackURL: fallbackURL
        ) else {
            return nil
        }

        return ArticleExtractionResult(
            title: finalTitle,
            contentHTML: finalHTML,
            textContent: finalText,
            excerpt: nonEmpty(excerpt),
            byline: nonEmpty(byline),
            url: fallbackURL
        )
    }

    private static func makeFallbackResult(from html: String, url: URL?, title: String?) -> ArticleExtractionResult? {
        let text = normalizeStructuredPlainText(plainText(fromHTML: html))
        guard let finalText = nonEmpty(text) else {
            return nil
        }

        let finalTitle = nonEmpty(title) ?? url?.host ?? "Untitled"

        guard hasMeaningfulBodyText(
            finalText,
            titleCandidates: [finalTitle, title],
            fallbackURL: url
        ) else {
            return nil
        }

        return ArticleExtractionResult(
            title: finalTitle,
            contentHTML: wrapPlainTextAsHTML(finalText),
            textContent: finalText,
            excerpt: nil,
            byline: nil,
            url: url
        )
    }

    private static func prepareHTML(_ html: String, url: URL?, title: String?) -> String {
        var injections: [String] = []

        if let url {
            injections.append(#"<base href="\#(escapeHTMLAttribute(url.absoluteString))">"#)
        }

        if let title = nonEmpty(title), !html.lowercased().contains("<title") {
            injections.append("<title>\(escapeHTMLText(title))</title>")
        }

        guard !injections.isEmpty else {
            return html
        }

        let headContent = injections.joined()

        if let headRange = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: headRange, with: "\(html[headRange])\(headContent)")
        }

        if let htmlRange = html.range(of: "<html[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: htmlRange, with: "\(html[htmlRange])<head>\(headContent)</head>")
        }

        return "<html><head>\(headContent)</head><body>\(html)</body></html>"
    }

    private static func documentTitle(fromHTML html: String) -> String? {
        guard let titleRange = html.range(
            of: "(?is)<title[^>]*>.*?</title>",
            options: .regularExpression
        ) else {
            return nil
        }

        let rawTitle = String(html[titleRange])
            .replacingOccurrences(of: "(?is)</?title[^>]*>", with: "", options: .regularExpression)

        return nonEmpty(normalizeStructuredPlainText(plainText(fromHTML: rawTitle)))
    }

    private static func preferredTitle(
        extractedTitle: String?,
        fallbackTitle: String?,
        fallbackURL: URL?
    ) -> String? {
        guard let extractedTitle = nonEmpty(extractedTitle) else {
            return nonEmpty(fallbackTitle)
        }

        if let host = fallbackURL?.host,
           normalizeComparison(extractedTitle) == normalizeComparison(host),
           let fallbackTitle = nonEmpty(fallbackTitle) {
            return fallbackTitle
        }

        return extractedTitle
    }

    private static func hasMeaningfulBodyText(
        _ text: String,
        titleCandidates: [String?],
        fallbackURL: URL?
    ) -> Bool {
        var normalizedText = normalizeComparison(text)
        guard !normalizedText.isEmpty else { return false }

        let removableTokens = titleCandidates.compactMap { nonEmpty($0) }
            + [fallbackURL?.host, fallbackURL?.absoluteString].compactMap { nonEmpty($0) }

        for token in removableTokens {
            let normalizedToken = normalizeComparison(token)
            guard !normalizedToken.isEmpty else { continue }
            normalizedText = normalizedText.replacingOccurrences(of: normalizedToken, with: " ")
        }

        normalizedText = normalizedText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return !normalizedText.isEmpty
    }

    private static func plainText(fromHTML html: String) -> String {
        var text = html
        let replacements = [
            ("(?is)<script\\b[^>]*>.*?</script>", " "),
            ("(?is)<style\\b[^>]*>.*?</style>", " "),
            ("(?is)<noscript\\b[^>]*>.*?</noscript>", " "),
            ("(?i)</(p|div|section|article|main|aside|header|footer|li|ul|ol|blockquote|pre|h1|h2|h3|h4|h5|h6)>", "\n\n"),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?is)<[^>]+>", " ")
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]

        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }

        return text
    }

    private static func normalizeStructuredPlainText(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        lines.reserveCapacity(normalizedNewlines.count / 40)

        var lastWasBlank = true
        for rawLine in normalizedNewlines.components(separatedBy: "\n") {
            let line = rawLine
                .replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                if !lastWasBlank {
                    lines.append("")
                    lastWasBlank = true
                }
                continue
            }

            lines.append(line)
            lastWasBlank = false
        }

        while lines.first?.isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        let joined = lines.joined(separator: "\n")
        if joined.contains("\n\n") {
            return joined
        }

        // Readability often emits one logical block per line with no blank lines.
        // Promote those separators to paragraph breaks so chunking can preserve structure.
        return joined.replacingOccurrences(of: "\n", with: "\n\n")
    }

    private static func normalizeComparison(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeHTML(_ html: String) -> String {
        html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wrapPlainTextAsHTML(_ text: String) -> String {
        "<p>\(escapeHTMLText(text))</p>"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func escapeHTMLText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTMLText(text)
    }
}

enum ReaderModeDocumentBuilder {
    static func document(for article: ArticleExtractionResult) -> String {
        let escapedTitle = escapeHTML(article.title)
        let escapedExcerpt = article.excerpt.map(escapeHTML)
        let escapedByline = article.byline.map(escapeHTML)
        let baseTag = article.url.map { #"<base href="\#(escapeHTML($0.absoluteString))">"# } ?? ""
        let metadata = [escapedByline, escapedExcerpt]
            .compactMap { $0 }
            .joined(separator: " | ")

        let metadataHTML = metadata.isEmpty
            ? ""
            : #"<p class="reader-meta">\#(metadata)</p>"#

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \(baseTag)
            <title>\(escapedTitle)</title>
            <style>
                :root {
                    color-scheme: light dark;
                    --reader-bg: #fafaf8;
                    --reader-surface: rgba(255, 255, 255, 0.92);
                    --reader-text: #222222;
                    --reader-muted: #666666;
                    --reader-link: #0b63ce;
                    --reader-border: rgba(15, 23, 42, 0.1);
                    --reader-code-bg: #f1f5f9;
                    --reader-shadow: 0 24px 48px rgba(15, 23, 42, 0.08);
                }

                @media (prefers-color-scheme: dark) {
                    :root {
                        --reader-bg: #111315;
                        --reader-surface: rgba(18, 21, 24, 0.96);
                        --reader-text: #edf2f7;
                        --reader-muted: #9aa4b2;
                        --reader-link: #84b7ff;
                        --reader-border: rgba(148, 163, 184, 0.18);
                        --reader-code-bg: #1f2937;
                        --reader-shadow: 0 24px 48px rgba(0, 0, 0, 0.3);
                    }
                }

                * { box-sizing: border-box; }

                html, body {
                    margin: 0;
                    padding: 0;
                    background:
                        radial-gradient(circle at top, rgba(11, 99, 206, 0.08), transparent 30%),
                        var(--reader-bg);
                    color: var(--reader-text);
                    font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Georgia, serif;
                    font-size: 19px;
                    line-height: 1.75;
                }

                body {
                    padding: 40px 20px 64px;
                }

                .reader-container {
                    max-width: 760px;
                    margin: 0 auto;
                    padding: 40px 44px 56px;
                    background: var(--reader-surface);
                    border: 1px solid var(--reader-border);
                    border-radius: 24px;
                    box-shadow: var(--reader-shadow);
                    backdrop-filter: blur(10px);
                }

                .reader-title {
                    margin: 0;
                    font-size: clamp(2.1rem, 4vw, 3rem);
                    line-height: 1.1;
                    letter-spacing: -0.03em;
                }

                .reader-meta {
                    margin: 16px 0 32px;
                    color: var(--reader-muted);
                    font-size: 0.95rem;
                    text-transform: uppercase;
                    letter-spacing: 0.08em;
                }

                .reader-body :is(h1, h2, h3, h4, h5, h6) {
                    font-family: "SF Pro Display", "Avenir Next", system-ui, sans-serif;
                    line-height: 1.2;
                    margin: 1.6em 0 0.6em;
                }

                .reader-body h1 { font-size: 1.8em; }
                .reader-body h2 { font-size: 1.45em; }
                .reader-body h3 { font-size: 1.2em; }

                .reader-body p,
                .reader-body ul,
                .reader-body ol,
                .reader-body blockquote,
                .reader-body pre {
                    margin: 1em 0;
                }

                .reader-body a {
                    color: var(--reader-link);
                    text-decoration-thickness: 1.5px;
                    text-underline-offset: 0.16em;
                }

                .reader-body img,
                .reader-body video {
                    display: block;
                    max-width: 100%;
                    height: auto;
                    margin: 1.4em auto;
                    border-radius: 16px;
                }

                .reader-body blockquote {
                    margin-left: 0;
                    padding: 0.2em 0 0.2em 1.2em;
                    border-left: 4px solid var(--reader-link);
                    color: var(--reader-muted);
                }

                .reader-body pre,
                .reader-body code {
                    font-family: "SF Mono", "Menlo", monospace;
                    background: var(--reader-code-bg);
                    border-radius: 10px;
                }

                .reader-body code {
                    padding: 0.15em 0.35em;
                    font-size: 0.9em;
                }

                .reader-body pre {
                    padding: 1em 1.2em;
                    overflow-x: auto;
                }

                .reader-body pre code {
                    padding: 0;
                    background: transparent;
                }

                .reader-body hr {
                    border: 0;
                    border-top: 1px solid var(--reader-border);
                    margin: 2em 0;
                }
            </style>
        </head>
        <body>
            <article class="reader-container">
                <header>
                    <h1 class="reader-title">\(escapedTitle)</h1>
                    \(metadataHTML)
                </header>
                <section class="reader-body">
                    \(article.contentHTML)
                </section>
            </article>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
