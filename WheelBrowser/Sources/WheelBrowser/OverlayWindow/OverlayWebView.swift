import SwiftUI
import WebKit

/// NSViewRepresentable that wraps WKWebView for use in overlay windows
/// Features: reader mode, in-overlay navigation (no history recording)
struct OverlayWebView: NSViewRepresentable {
    let url: URL
    var item: OverlayWindowItem
    @Binding var isLoading: Bool
    @Binding var isReaderMode: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = BrowserWebViewConfigurationFactory.shared.makeConfiguration(surface: .overlay)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Load the initial URL
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Handle reader mode toggle
        if isReaderMode != context.coordinator.lastReaderModeState {
            context.coordinator.lastReaderModeState = isReaderMode
            if isReaderMode {
                context.coordinator.enableReaderMode(in: webView)
            } else {
                context.coordinator.disableReaderMode(in: webView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, isLoading: $isLoading, isReaderMode: $isReaderMode)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let item: OverlayWindowItem
        @Binding var isLoading: Bool
        @Binding var isReaderMode: Bool
        var lastReaderModeState: Bool = false
        private var originalHTML: String?

        init(item: OverlayWindowItem, isLoading: Binding<Bool>, isReaderMode: Binding<Bool>) {
            self.item = item
            self._isLoading = isLoading
            self._isReaderMode = isReaderMode
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.isLoading = false

                // Update the overlay window's title
                if let title = webView.title, !title.isEmpty {
                    self.item.title = title
                } else if let host = webView.url?.host {
                    self.item.title = host
                }

                if let currentURL = webView.url {
                    self.item.url = currentURL
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.isLoading = false
            }
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = "Alert"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Confirm"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle popup windows - load in the same overlay instead of opening new window
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: - Reader Mode

        func enableReaderMode(in webView: WKWebView) {
            // Store original HTML for restore
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                if let html = result as? String {
                    self?.originalHTML = html
                }
            }

            let readerScript = """
            (function() {
                // Find the main content
                function getMainContent() {
                    // Try common article selectors
                    const selectors = [
                        'article',
                        '[role="main"]',
                        'main',
                        '.post-content',
                        '.article-content',
                        '.entry-content',
                        '.content',
                        '#content',
                        '.post',
                        '.article'
                    ];

                    for (const sel of selectors) {
                        const el = document.querySelector(sel);
                        if (el && el.innerText.length > 500) {
                            return el;
                        }
                    }

                    // Fallback: find largest text block
                    const paragraphs = document.querySelectorAll('p');
                    let bestParent = null;
                    let maxLength = 0;

                    paragraphs.forEach(p => {
                        const parent = p.parentElement;
                        if (parent) {
                            const len = parent.innerText.length;
                            if (len > maxLength) {
                                maxLength = len;
                                bestParent = parent;
                            }
                        }
                    });

                    return bestParent || document.body;
                }

                const content = getMainContent();
                const title = document.title;

                // Get all images from content
                const images = content.querySelectorAll('img');
                let imageHTML = '';
                images.forEach(img => {
                    if (img.src && img.width > 100) {
                        imageHTML += '<img src="' + img.src + '" style="max-width: 100%; height: auto; margin: 1em 0;">';
                    }
                });

                // Get text content with paragraph structure
                const paragraphs = content.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote, pre, code');
                let textHTML = '';
                paragraphs.forEach(el => {
                    const tag = el.tagName.toLowerCase();
                    textHTML += '<' + tag + '>' + el.innerHTML + '</' + tag + '>';
                });

                if (!textHTML) {
                    textHTML = '<p>' + content.innerText + '</p>';
                }

                // Check if dark mode
                const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                const bgColor = isDark ? '#1a1a1a' : '#fafafa';
                const textColor = isDark ? '#e0e0e0' : '#333';
                const linkColor = isDark ? '#6db3f2' : '#0066cc';

                document.documentElement.innerHTML = `
                    <head>
                        <meta charset="UTF-8">
                        <meta name="viewport" content="width=device-width, initial-scale=1.0">
                        <title>${title}</title>
                        <style>
                            * { box-sizing: border-box; }
                            html, body {
                                margin: 0;
                                padding: 0;
                                background: ${bgColor};
                                color: ${textColor};
                                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Georgia, serif;
                                font-size: 18px;
                                line-height: 1.7;
                            }
                            .reader-container {
                                max-width: 680px;
                                margin: 0 auto;
                                padding: 2em 1.5em;
                            }
                            h1 {
                                font-size: 1.8em;
                                line-height: 1.3;
                                margin-bottom: 0.5em;
                                font-weight: 600;
                            }
                            h2, h3, h4 {
                                margin-top: 1.5em;
                                margin-bottom: 0.5em;
                                font-weight: 600;
                            }
                            p {
                                margin: 1em 0;
                            }
                            a {
                                color: ${linkColor};
                                text-decoration: none;
                            }
                            a:hover {
                                text-decoration: underline;
                            }
                            img {
                                max-width: 100%;
                                height: auto;
                                border-radius: 4px;
                            }
                            blockquote {
                                border-left: 3px solid ${linkColor};
                                margin: 1em 0;
                                padding-left: 1em;
                                opacity: 0.9;
                            }
                            pre, code {
                                background: ${isDark ? '#2d2d2d' : '#f0f0f0'};
                                padding: 0.2em 0.4em;
                                border-radius: 3px;
                                font-family: 'SF Mono', Menlo, monospace;
                                font-size: 0.9em;
                            }
                            pre {
                                padding: 1em;
                                overflow-x: auto;
                            }
                            li {
                                margin: 0.5em 0;
                            }
                        </style>
                    </head>
                    <body>
                        <div class="reader-container">
                            <h1>${title}</h1>
                            ${textHTML}
                        </div>
                    </body>
                `;
            })();
            """

            webView.evaluateJavaScript(readerScript) { _, _ in }
        }

        func disableReaderMode(in webView: WKWebView) {
            // Reload the page to restore original content
            webView.reload()
        }
    }
}
