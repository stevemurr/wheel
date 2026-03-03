import WebKit
import AppKit

/// WKWebView subclass that replaces WebKit's native context menu with a custom
/// `NSMenu` built from a JS hit-test.
///
/// The native context menu is unreliable for "Open Link in New Tab" because
/// `willOpenMenu` is synchronous but JS link detection is async. This subclass
/// suppresses the native menu entirely, runs a JS hit-test on right-click, waits
/// for the result (with a 200ms safety timeout), then shows a custom menu via
/// `popUp(positioning:at:in:)`.
class BrowserWebView: WKWebView {

    /// The location (in view coordinates) of the last right-click.
    private var lastRightClickLocation: NSPoint = .zero

    /// Generation counter to discard stale JS callbacks from previous right-clicks.
    private var rightClickGeneration: UInt64 = 0

    /// The most recent hit-test result, used by action methods.
    private var lastHitTest: ContextMenuHitTest?

    // MARK: - Suppress native context menu

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: - Right-click → JS hit-test → custom menu

    override func rightMouseDown(with event: NSEvent) {
        lastRightClickLocation = convert(event.locationInWindow, from: nil)
        lastHitTest = nil
        rightClickGeneration &+= 1
        let gen = rightClickGeneration

        let cssX = lastRightClickLocation.x / pageZoom
        let cssY = (bounds.height - lastRightClickLocation.y) / pageZoom

        // Both closures run on main thread; captured local var is safe.
        var menuShown = false

        // Safety timeout: if JS hangs, show a minimal navigation-only menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !menuShown, self.rightClickGeneration == gen else { return }
            menuShown = true
            self.lastHitTest = .empty
            self.showCustomMenu(for: .empty, at: self.lastRightClickLocation)
        }

        evaluateJavaScript(ContextMenuScripts.hitTest(cssX: cssX, cssY: cssY)) { [weak self] result, _ in
            guard let self, self.rightClickGeneration == gen else { return }

            let hitTest: ContextMenuHitTest
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ContextMenuHitTest.self, from: data) {
                hitTest = decoded
            } else {
                hitTest = .empty
            }

            self.lastHitTest = hitTest

            guard !menuShown else { return }
            menuShown = true
            self.showCustomMenu(for: hitTest, at: self.lastRightClickLocation)
        }
    }

    /// Build and display the custom context menu at the given view location.
    private func showCustomMenu(for hitTest: ContextMenuHitTest, at location: NSPoint) {
        let menu = ContextMenuBuilder.buildMenu(for: hitTest, target: self)

        // Disable Back/Forward based on navigation state.
        for item in menu.items {
            if item.action == #selector(contextAction_goBack(_:)) {
                item.isEnabled = canGoBack
            } else if item.action == #selector(contextAction_goForward(_:)) {
                item.isEnabled = canGoForward
            }
        }

        menu.popUp(positioning: nil, at: location, in: self)
    }

    // MARK: - Action handlers

    @objc func contextAction_openLinkInNewTab(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
    }

    @objc func contextAction_copyLinkAddress(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String else { return }
        PasteboardHelper.copy(urlString)
    }

    @objc func contextAction_openImageInNewTab(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
    }

    @objc func contextAction_saveImageAs(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                guard let tempURL, error == nil else { return }
                try? FileManager.default.moveItem(at: tempURL, to: dest)
            }
            task.resume()
            _ = self // prevent unused warning; weak capture is intentional
        }
    }

    @objc func contextAction_copyImage(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
        }.resume()
    }

    @objc func contextAction_copyImageAddress(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String else { return }
        PasteboardHelper.copy(urlString)
    }

    @objc func contextAction_openMediaInNewTab(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
    }

    @objc func contextAction_copyMediaAddress(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String else { return }
        PasteboardHelper.copy(urlString)
    }

    @objc func contextAction_cut(_ sender: NSMenuItem) {
        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
    }

    @objc func contextAction_copy(_ sender: NSMenuItem) {
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
    }

    @objc func contextAction_paste(_ sender: NSMenuItem) {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
    }

    @objc func contextAction_selectAll(_ sender: NSMenuItem) {
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
    }

    @objc func contextAction_copySelection(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        PasteboardHelper.copy(text)
    }

    @objc func contextAction_searchWebFor(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
        NotificationCenter.default.post(name: .openLinkInNewTab, object: url)
    }

    @objc func contextAction_goBack(_ sender: NSMenuItem) {
        goBack()
    }

    @objc func contextAction_goForward(_ sender: NSMenuItem) {
        goForward()
    }

    @objc func contextAction_reload(_ sender: NSMenuItem) {
        reload()
    }
}
