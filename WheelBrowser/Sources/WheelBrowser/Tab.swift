import Foundation
import WebKit
import AppKit

class Tab: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading: Bool = false
    @Published var lastError: NavigationError?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var zoomLevel: Double = 1.0
    @Published var isFindBarVisible: Bool = false
    @Published var findSearchText: String = ""
    @Published var hasActiveAgent: Bool = false
    @Published var agentProgress: String = ""

    let webView: WKWebView

    /// Lazy controllers backed by webView
    private lazy var findController = FindInPageController(webView: webView)
    private lazy var pipController = PictureInPictureController(webView: webView)

    /// Computed display title that handles empty/default titles gracefully
    /// Returns the URL host (without www.) if title is empty or "New Tab"
    var displayTitle: String {
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

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true

        // Enable Picture-in-Picture using KVC (required on macOS, private API)
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")

        // Inject dark mode script at document start to prevent flash of light content
        config.userContentController.addUserScript(DarkModeScripts.createUserScript())

        // Inject link hover detection script for link previews
        config.userContentController.addUserScript(LinkHoverScripts.createUserScript())

        // Inject anti-detection scripts in headless mode
        if HeadlessConfig.current.enabled {
            config.userContentController.addUserScript(AntiDetectionScripts.createUserScript())
        }

        // Inject cookie banner dismissal script when annoyances blocking is enabled
        if AppSettings.shared.adBlockingEnabled,
           ContentBlockerManager.isCategoryEnabled(.annoyances) {
            config.userContentController.addUserScript(CookieBannerScripts.createUserScript())
        }

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.allowsBackForwardNavigationGestures = true

        // Apply ad blocking rules after webView is created
        if AppSettings.shared.adBlockingEnabled {
            Task { @MainActor in
                await ContentBlockerManager.shared.applyRules(to: self.webView)
            }
        }
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
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stopLoading() {
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
        webView.pageZoom = level
    }

    // MARK: - Find in Page

    func showFindBar() {
        isFindBarVisible = true
    }

    func hideFindBar() {
        isFindBarVisible = false
        findSearchText = ""
        findController.clearHighlights()
    }

    func findInPage(_ searchText: String) {
        findSearchText = searchText
        findController.findInPage(searchText)
    }

    func findNext() {
        findController.findNext()
    }

    func findPrevious() {
        findController.findPrevious()
    }

    // MARK: - Screenshot Capture

    /// Captures a screenshot of this tab for preview purposes
    func captureScreenshot() async {
        await TabScreenshotManager.shared.captureScreenshot(for: self)
    }

    // MARK: - Picture in Picture

    func togglePictureInPicture() {
        pipController.toggle()
    }

    // MARK: - Cleanup

    /// Cleans up the tab by stopping any pending loads and pausing all media
    func cleanup() {
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
