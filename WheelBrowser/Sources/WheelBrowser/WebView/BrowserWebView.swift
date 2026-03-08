import WebKit
import AppKit

/// WKWebView subclass that replaces WebKit's native context menu with a custom
/// SwiftUI overlay built from a JS hit-test.
///
/// The native context menu is unreliable for "Open Link in New Tab" because
/// `willOpenMenu` is synchronous but JS link detection is async. This subclass
/// suppresses the native menu entirely, runs a JS hit-test on right-click, waits
/// for the result (with a 200ms safety timeout), then publishes state to
/// `ContextMenuState` which renders a SwiftUI overlay.
class BrowserWebView: WKWebView {

    /// The location (in view coordinates) of the last right-click.
    private var lastRightClickLocation: NSPoint = .zero

    /// Generation counter to discard stale JS callbacks from previous right-clicks.
    private var rightClickGeneration: UInt64 = 0

    // MARK: - Suppress native context menu

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: - Right-click → JS hit-test → custom overlay

    override func rightMouseDown(with event: NSEvent) {
        lastRightClickLocation = convert(event.locationInWindow, from: nil)
        rightClickGeneration &+= 1
        let gen = rightClickGeneration

        // WKWebView.isFlipped == true, so local coordinates are already top-left
        // origin — matching CSS viewport space. No Y inversion needed.
        let cssX = lastRightClickLocation.x / pageZoom
        let cssY = lastRightClickLocation.y / pageZoom

        // Both closures run on main thread; captured local var is safe.
        var menuShown = false

        // Safety timeout: if JS hangs, show a minimal navigation-only menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !menuShown, self.rightClickGeneration == gen else { return }
            menuShown = true
            self.showCustomMenu(for: .empty)
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

            guard !menuShown else { return }
            menuShown = true
            self.showCustomMenu(for: hitTest)
        }
    }

    /// Publish hit-test to `ContextMenuState` so the SwiftUI overlay renders.
    private func showCustomMenu(for hitTest: ContextMenuHitTest) {
        guard let window else { return }

        // Convert local click to window coordinates (AppKit, origin bottom-left).
        let windowPoint = convert(lastRightClickLocation, to: nil)

        // contentLayoutRect is the area the SwiftUI GeometryReader occupies —
        // it excludes the title bar in a .fullSizeContentView window.
        let content = window.contentLayoutRect

        let swiftUIPoint = CGPoint(
            x: windowPoint.x - content.origin.x,
            y: content.height - (windowPoint.y - content.origin.y)
        )

        ContextMenuState.shared.show(
            at: swiftUIPoint,
            hitTest: hitTest,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            source: self
        )
    }

    // MARK: - Action dispatch

    /// Execute a context menu action. Called by the SwiftUI overlay.
    func executeContextAction(_ action: ContextMenuAction) {
        switch action {
        case .openLinkInNewTab(let url):
            guard let url = URL(string: url) else { return }
            NotificationCenter.default.post(name: .openLinkInNewTab, object: url)

        case .copyLinkAddress(let url):
            PasteboardHelper.copy(url)

        case .openImageInNewTab(let url):
            guard let url = URL(string: url) else { return }
            NotificationCenter.default.post(name: .openLinkInNewTab, object: url)

        case .saveImageAs(let urlString):
            guard let url = URL(string: urlString) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let dest = panel.url else { return }
                let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                    guard let tempURL, error == nil else { return }
                    try? FileManager.default.moveItem(at: tempURL, to: dest)
                }
                task.resume()
            }

        case .copyImage(let urlString):
            guard let url = URL(string: urlString) else { return }
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard let data, error == nil, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }.resume()

        case .copyImageAddress(let url):
            PasteboardHelper.copy(url)

        case .openMediaInNewTab(let url, _):
            guard let url = URL(string: url) else { return }
            NotificationCenter.default.post(name: .openLinkInNewTab, object: url)

        case .copyMediaAddress(let url):
            PasteboardHelper.copy(url)

        case .cut:
            NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)

        case .copy:
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)

        case .paste:
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)

        case .selectAll:
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)

        case .copySelection(let text):
            PasteboardHelper.copy(text)

        case .searchWebFor(let text):
            guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
            NotificationCenter.default.post(name: .openLinkInNewTab, object: url)

        case .openTodayNote:
            NotificationCenter.default.post(name: .openTodayNote, object: nil)

        case .newNoteFromPage:
            NotificationCenter.default.post(name: .newNoteFromPage, object: nil)

        case .goBack:
            goBack()

        case .goForward:
            goForward()

        case .reload:
            reload()
        }
    }
}
