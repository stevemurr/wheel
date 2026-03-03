import WebKit
import AppKit

/// WKWebView subclass that adds "Open Link in New Tab" to the native context menu.
///
/// Uses multiple WebKit context menu item identifiers as reliable link indicators,
/// with a JS fallback for edge cases. JS runs in the background purely for URL
/// extraction, not for deciding whether to show the menu item.
class BrowserWebView: WKWebView {

    /// The location (in view coordinates) of the last right-click.
    private var lastRightClickLocation: NSPoint = .zero

    /// The link URL detected at the last right-click location, if any.
    private var lastDetectedLinkURL: URL?

    /// Generation counter to discard stale JS callbacks from previous right-clicks.
    private var rightClickGeneration: UInt64 = 0

    /// Cached icon for the "Open Link in New Tab" menu item.
    private static let newTabIcon: NSImage? = {
        let img = NSImage(systemSymbolName: "plus.rectangle.on.rectangle",
                          accessibilityDescription: "Open in new tab")
        img?.size = NSSize(width: 16, height: 16)
        img?.isTemplate = true
        return img
    }()

    /// WebKit menu item identifiers that indicate a link context.
    /// Checking multiple identifiers makes detection robust — if WebKit omits one
    /// (e.g., on certain page configurations), others may still be present.
    private static let linkIdentifiers: Set<String> = [
        "WKMenuItemIdentifierOpenLinkInNewWindow",
        "WKMenuItemIdentifierCopyLink",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierOpenLink",
    ]

    /// The preferred identifier to insert after (natural menu ordering).
    private static let preferredInsertAfter = "WKMenuItemIdentifierOpenLinkInNewWindow"

    // MARK: - Link detection JS

    private static func linkDetectionJS(cssX: CGFloat, cssY: CGFloat) -> String {
        """
        (function() {
            var el = document.elementFromPoint(\(cssX), \(cssY));
            while (el) {
                if (el.tagName === 'A' && el.href) return el.href;
                if (el.parentElement) {
                    el = el.parentElement;
                } else {
                    var root = el.getRootNode();
                    if (root && root !== document && root.host) {
                        el = root.host;
                    } else {
                        break;
                    }
                }
            }
            return '';
        })()
        """
    }

    // MARK: - Right-click link detection

    override func rightMouseDown(with event: NSEvent) {
        lastRightClickLocation = convert(event.locationInWindow, from: nil)
        lastDetectedLinkURL = nil
        rightClickGeneration &+= 1
        let expectedGeneration = rightClickGeneration

        // Fire JS in background for URL extraction (not for menu visibility).
        let cssX = lastRightClickLocation.x / pageZoom
        let cssY = (bounds.height - lastRightClickLocation.y) / pageZoom

        evaluateJavaScript(Self.linkDetectionJS(cssX: cssX, cssY: cssY)) { [weak self] result, _ in
            guard let self, self.rightClickGeneration == expectedGeneration else { return }
            if let href = result as? String, !href.isEmpty {
                self.lastDetectedLinkURL = URL(string: href)
            }
        }

        // Show menu immediately — no timeout needed.
        super.rightMouseDown(with: event)
    }

    // MARK: - Context menu

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // Scan for any WebKit link-related menu item. Track the best insertion
        // position and opportunistically extract the URL.
        var insertAfterIndex: Int?
        var fallbackIndex: Int?
        var webKitLinkURL: URL?

        for (index, item) in menu.items.enumerated() {
            guard let rawId = item.identifier?.rawValue,
                  Self.linkIdentifiers.contains(rawId) else { continue }

            // Extract URL from the first link-related item that has one.
            if webKitLinkURL == nil, let url = item.representedObject as? URL {
                webKitLinkURL = url
            }

            if rawId == Self.preferredInsertAfter {
                // Best position: right after "Open Link in New Window".
                insertAfterIndex = index + 1
                break
            }
            // Record first link-related item as fallback insertion point.
            if fallbackIndex == nil {
                fallbackIndex = index + 1
            }
        }

        let webKitDetectedLink = insertAfterIndex != nil || fallbackIndex != nil
        // Use JS result as secondary signal when WebKit didn't add link items
        // (e.g., pages that modify the context menu). Only used when JS has
        // already completed — no timing dependency.
        let jsDetectedLink = !webKitDetectedLink && lastDetectedLinkURL != nil

        if webKitDetectedLink || jsDetectedLink {
            // Populate lastDetectedLinkURL from WebKit if JS hasn't finished.
            if lastDetectedLinkURL == nil {
                lastDetectedLinkURL = webKitLinkURL
            }

            let newTabItem = NSMenuItem(
                title: "Open Link in New Tab",
                action: #selector(openLinkInNewTab(_:)),
                keyEquivalent: ""
            )
            newTabItem.target = self
            newTabItem.image = Self.newTabIcon

            // Insert after WebKit's link item, or at top for JS-only detection.
            let targetIndex = insertAfterIndex ?? fallbackIndex ?? 0
            menu.insertItem(newTabItem, at: min(targetIndex, menu.items.count))
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
        evaluateJavaScript(Self.linkDetectionJS(cssX: cssX, cssY: cssY)) { result, _ in
            if let href = result as? String, !href.isEmpty, let url = URL(string: href) {
                NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
            }
        }
    }
}
