import WebKit
import AppKit

/// WKWebView subclass that adds "Open Link in New Tab" to the native context menu.
///
/// Uses WebKit's own context menu items as the reliable link indicator instead of
/// racing an async JS evaluation against a timeout. JS runs in the background purely
/// for URL extraction, not for deciding whether to show the menu item.
class BrowserWebView: WKWebView {

    /// The location (in view coordinates) of the last right-click.
    private var lastRightClickLocation: NSPoint = .zero

    /// The link URL detected at the last right-click location, if any.
    private var lastDetectedLinkURL: URL?

    // MARK: - Right-click link detection

    override func rightMouseDown(with event: NSEvent) {
        lastRightClickLocation = convert(event.locationInWindow, from: nil)
        lastDetectedLinkURL = nil

        // Fire JS in background for URL extraction (not for menu visibility).
        let cssX = lastRightClickLocation.x / pageZoom
        let cssY = (bounds.height - lastRightClickLocation.y) / pageZoom

        let js = """
        (function() {
            var el = document.elementFromPoint(\(cssX), \(cssY));
            while (el) {
                if (el.tagName === 'A' && el.href) return el.href;
                el = el.parentElement;
            }
            return '';
        })()
        """

        evaluateJavaScript(js) { [weak self] result, _ in
            if let href = result as? String, !href.isEmpty {
                self?.lastDetectedLinkURL = URL(string: href)
            }
        }

        // Show menu immediately — no timeout needed.
        super.rightMouseDown(with: event)
    }

    // MARK: - Context menu

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // Primary: check WebKit's own menu item identifier (locale-independent).
        let webKitLinkItemIndex = menu.items.firstIndex {
            $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow"
        }

        if webKitLinkItemIndex != nil || lastDetectedLinkURL != nil {
            // Opportunistically extract URL from WebKit's item if JS hasn't finished.
            if lastDetectedLinkURL == nil, let idx = webKitLinkItemIndex {
                if let url = menu.items[idx].representedObject as? URL {
                    lastDetectedLinkURL = url
                }
            }

            let newTabItem = NSMenuItem(
                title: "Open Link in New Tab",
                action: #selector(openLinkInNewTab(_:)),
                keyEquivalent: ""
            )
            newTabItem.target = self

            // Insert after WebKit's "Open Link in New Window" if present, else at top.
            let insertIndex = (webKitLinkItemIndex ?? 0) + 1
            menu.insertItem(newTabItem, at: min(insertIndex, menu.items.count))
        }

        super.willOpenMenu(menu, with: event)
    }

    @objc private func openLinkInNewTab(_ sender: NSMenuItem) {
        if let url = lastDetectedLinkURL {
            NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
            return
        }

        // Fallback: re-run JS with saved coordinates (extremely unlikely path).
        let cssX = lastRightClickLocation.x / pageZoom
        let cssY = (bounds.height - lastRightClickLocation.y) / pageZoom
        let js = """
        (function() {
            var el = document.elementFromPoint(\(cssX), \(cssY));
            while (el) {
                if (el.tagName === 'A' && el.href) return el.href;
                el = el.parentElement;
            }
            return '';
        })()
        """
        evaluateJavaScript(js) { result, _ in
            if let href = result as? String, !href.isEmpty, let url = URL(string: href) {
                NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
            }
        }
    }
}
