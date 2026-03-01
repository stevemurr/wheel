import Foundation
import WebKit

/// Handles find-in-page JavaScript execution against a WKWebView.
class FindInPageController {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func findInPage(_ searchText: String) {
        guard let webView = webView, !searchText.isEmpty else {
            clearHighlights()
            return
        }

        let escapedText = searchText.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        (function() {
            // Clear previous highlights
            document.querySelectorAll('.wheel-find-highlight').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });

            const searchText = '\(escapedText)';
            if (!searchText) return { found: 0 };

            const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );

            const nodesToHighlight = [];
            let node;
            while (node = walker.nextNode()) {
                if (node.nodeValue.toLowerCase().includes(searchText.toLowerCase())) {
                    nodesToHighlight.push(node);
                }
            }

            let count = 0;
            nodesToHighlight.forEach(textNode => {
                const text = textNode.nodeValue;
                const regex = new RegExp('(' + searchText.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&') + ')', 'gi');
                const parts = text.split(regex);

                if (parts.length > 1) {
                    const fragment = document.createDocumentFragment();
                    parts.forEach(part => {
                        if (part.toLowerCase() === searchText.toLowerCase()) {
                            const span = document.createElement('span');
                            span.className = 'wheel-find-highlight';
                            span.style.backgroundColor = '#ffff00';
                            span.style.color = '#000000';
                            span.textContent = part;
                            fragment.appendChild(span);
                            count++;
                        } else {
                            fragment.appendChild(document.createTextNode(part));
                        }
                    });
                    textNode.parentNode.replaceChild(fragment, textNode);
                }
            });

            // Scroll to first match
            const firstMatch = document.querySelector('.wheel-find-highlight');
            if (firstMatch) {
                firstMatch.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }

            return { found: count };
        })();
        """

        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                Log.Browser.debug("Find in page JS failed: \(error.localizedDescription)")
            }
        }
    }

    func findNext() {
        guard let webView = webView else { return }

        let script = """
        (function() {
            const highlights = document.querySelectorAll('.wheel-find-highlight');
            if (highlights.length === 0) return;

            let currentIndex = -1;
            highlights.forEach((el, i) => {
                if (el.classList.contains('wheel-find-current')) {
                    currentIndex = i;
                    el.classList.remove('wheel-find-current');
                    el.style.backgroundColor = '#ffff00';
                }
            });

            const nextIndex = (currentIndex + 1) % highlights.length;
            const nextEl = highlights[nextIndex];
            nextEl.classList.add('wheel-find-current');
            nextEl.style.backgroundColor = '#ff9500';
            nextEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        })();
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                Log.Browser.debug("Find next JS failed: \(error.localizedDescription)")
            }
        }
    }

    func findPrevious() {
        guard let webView = webView else { return }

        let script = """
        (function() {
            const highlights = document.querySelectorAll('.wheel-find-highlight');
            if (highlights.length === 0) return;

            let currentIndex = 0;
            highlights.forEach((el, i) => {
                if (el.classList.contains('wheel-find-current')) {
                    currentIndex = i;
                    el.classList.remove('wheel-find-current');
                    el.style.backgroundColor = '#ffff00';
                }
            });

            const prevIndex = (currentIndex - 1 + highlights.length) % highlights.length;
            const prevEl = highlights[prevIndex];
            prevEl.classList.add('wheel-find-current');
            prevEl.style.backgroundColor = '#ff9500';
            prevEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        })();
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                Log.Browser.debug("Find previous JS failed: \(error.localizedDescription)")
            }
        }
    }

    func clearHighlights() {
        guard let webView = webView else { return }

        let script = """
        (function() {
            document.querySelectorAll('.wheel-find-highlight').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });
        })();
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                Log.Browser.debug("Clear find highlights JS failed: \(error.localizedDescription)")
            }
        }
    }
}
