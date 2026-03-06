import Foundation
import WebKit
import AppKit

@Observable
class Tab: Identifiable {
    let id: UUID
    var title: String = "New Tab"
    var url: URL?
    var isLoading: Bool = false
    var lastError: NavigationError?
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var zoomLevel: Double = 1.0
    var isFindBarVisible: Bool = false
    var findSearchText: String = ""
    var hasActiveAgent: Bool = false
    var agentProgress: String = ""
    var isChatTab: Bool = false

    /// Set to true once a message has been sent in this tab's conversation.
    /// Once true, the chat tab latch becomes permanent.
    var hasConversationStarted: Bool = false

    /// Transient UI intent used to decide whether a blank tab should latch
    /// into full-page chat, instead of inheriting shared OmniBar chat mode.
    var hasExplicitChatFocusIntent: Bool = false

    /// Each tab has its own conversation ID for per-tab chat isolation.
    var conversationId: UUID = UUID()

    /// Backing storage for the lazily-created WKWebView.
    /// Chat tabs that never render web content avoid the ~30-50MB overhead.
    private var _webView: WKWebView?

    /// The WKWebView backing this tab. Created lazily on first access.
    var webView: WKWebView {
        if let wv = _webView { return wv }
        let wv = Tab.createWebView()
        _webView = wv
        return wv
    }

    /// Whether a WKWebView has been allocated for this tab.
    var hasWebView: Bool { _webView != nil }

    /// Lazy controllers backed by webView
    @ObservationIgnored private lazy var findController = FindInPageController(webView: webView)
    @ObservationIgnored private lazy var pipController = PictureInPictureController(webView: webView)

    /// Computed display title that handles empty/default titles gracefully
    /// Returns the URL host (without www.) if title is empty or "New Tab"
    var displayTitle: String {
        if isChatTab && (title.isEmpty || title == "New Tab") {
            return "Chat"
        }
        if title.isEmpty || title == "New Tab" {
            if let domain = url?.cleanDomain, !domain.isEmpty {
                return domain
            }
            return "New Tab"
        }
        return title
    }

    // Zoom constants
    private let minZoom: Double = 0.5
    private let maxZoom: Double = 3.0
    private let zoomStep: Double = 0.1

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        url: URL? = nil,
        isChatTab: Bool = false,
        hasConversationStarted: Bool = false,
        conversationId: UUID = UUID()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.isChatTab = isChatTab
        self.hasConversationStarted = hasConversationStarted
        self.conversationId = conversationId
    }

    /// Creates a fully-configured WKWebView for browsing.
    private static func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true

        // Enable Picture-in-Picture using KVC (required on macOS, private API)
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")

        // Inject link hover detection script for link previews
        config.userContentController.addUserScript(LinkHoverScripts.createUserScript())

        // Inject anti-detection scripts in headless mode
        if HeadlessConfig.current.enabled {
            config.userContentController.addUserScript(AntiDetectionScripts.createUserScript())
        }

        let webView = BrowserWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true

        return webView
    }

    func load(_ urlString: String) {
        var urlToLoad = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https if no scheme provided
        if !urlToLoad.contains("://") {
            // Check if it looks like a URL or a search query
            if urlToLoad.contains(".") && !urlToLoad.contains(" ") {
                urlToLoad = "https://\(urlToLoad)"
            } else {
                // Treat as search query
                let encoded = urlToLoad.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlToLoad
                urlToLoad = "https://duckduckgo.com/?q=\(encoded)"
            }
        }

        if let url = URL(string: urlToLoad) {
            self.url = url
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() {
        guard hasWebView else { return }
        webView.goBack()
    }

    func goForward() {
        guard hasWebView else { return }
        webView.goForward()
    }

    func reload() {
        guard hasWebView else { return }
        webView.reload()
    }

    func stopLoading() {
        guard hasWebView else { return }
        webView.stopLoading()
    }

    // MARK: - Zoom Controls

    func zoomIn() {
        let newZoom = min(zoomLevel + zoomStep, maxZoom)
        setZoom(newZoom)
    }

    func zoomOut() {
        let newZoom = max(zoomLevel - zoomStep, minZoom)
        setZoom(newZoom)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    private func setZoom(_ level: Double) {
        zoomLevel = level
        guard hasWebView else { return }
        webView.pageZoom = level
    }

    // MARK: - Find in Page

    func showFindBar() {
        isFindBarVisible = true
    }

    func hideFindBar() {
        isFindBarVisible = false
        findSearchText = ""
        guard hasWebView else { return }
        findController.clearHighlights()
    }

    func findInPage(_ searchText: String) {
        guard hasWebView else { return }
        findSearchText = searchText
        findController.findInPage(searchText)
    }

    func findNext() {
        guard hasWebView else { return }
        findController.findNext()
    }

    func findPrevious() {
        guard hasWebView else { return }
        findController.findPrevious()
    }

    // MARK: - Screenshot Capture

    /// Captures a screenshot of this tab for preview purposes
    func captureScreenshot() async {
        await TabScreenshotManager.shared.captureScreenshot(for: self)
    }

    // MARK: - Picture in Picture

    func togglePictureInPicture() {
        guard hasWebView else { return }
        pipController.toggle()
    }

    // MARK: - Focus Handoff

    /// Blurs any active DOM element before the OmniBar takes focus.
    /// This prevents WKWebView-owned text inputs from keeping browser-level
    /// autofill surfaces alive while the app switches to a native command field.
    func relinquishPageInputFocus() {
        guard hasWebView else { return }

        webView.evaluateJavaScript(
            """
            (() => {
                const active = document.activeElement;
                if (active && typeof active.blur === 'function') {
                    active.blur();
                    return true;
                }
                return false;
            })();
            """,
            completionHandler: nil
        )

        guard let window = webView.window else { return }
        if let responderView = window.firstResponder as? NSView,
           responderView.isDescendant(of: webView) {
            window.makeFirstResponder(nil)
        }
    }

    // MARK: - Cleanup

    /// Cleans up the tab by stopping any pending loads and pausing all media.
    /// No-op if the WebView was never created (e.g. chat tabs).
    func cleanup() {
        guard let webView = _webView else { return }
        webView.stopLoading()

        // Pause and clear all media sources to stop audio/video
        let script = """
        document.querySelectorAll('video, audio').forEach(function(m) { m.pause(); m.src = ''; m.load(); });
        """
        webView.evaluateJavaScript(script) { _, _ in
            // Ignore errors - cleanup is best-effort
        }
    }

    deinit {
        cleanup()
    }
}
