import Foundation
import WebKit

/// Factory for the link hover/click detection user script injected into web pages.
enum LinkHoverScripts {
    /// Creates a WKUserScript that detects Cmd+Click on links for overlay windows.
    static func createUserScript() -> WKUserScript {
        let script = """
        (function() {
            if (window.__wheelLinkHoverInstalled) return;
            window.__wheelLinkHoverInstalled = true;

            function findLinkElement(el) {
                while (el && el !== document.body) {
                    if (el.tagName === 'A' && el.href) return el;
                    el = el.parentElement;
                }
                return null;
            }

            // Handle click events for Cmd+Click (overlay)
            document.addEventListener('click', function(e) {
                let target = e.target;
                while (target && target.tagName !== 'A') {
                    target = target.parentElement;
                }
                if (!target || !target.href || !target.href.startsWith('http')) return;

                // Cmd+Click (metaKey) - Open overlay window
                if (e.metaKey) {
                    e.preventDefault();
                    e.stopPropagation();

                    window.webkit.messageHandlers.overlayWindow.postMessage({
                        type: 'openOverlay',
                        url: target.href,
                        text: target.textContent?.trim() || target.href,
                        x: e.clientX,
                        y: e.clientY
                    });
                    return;
                }
            }, true);
        })();
        """

        return WKUserScript(
            source: script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}
