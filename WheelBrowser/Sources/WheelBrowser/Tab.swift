import Foundation
import WebKit
import AppKit

@Observable
class Tab: Identifiable {
    let id: UUID
    var title: String = "New Tab"
    var url: URL?
    var isLoading: Bool = false
    var isReaderMode: Bool = false
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
    @ObservationIgnored private var pendingReloadURL: URL?
    var webViewRevision: UUID = UUID()

    /// The WKWebView backing this tab. Created lazily on first access.
    var webView: WKWebView {
        if let wv = _webView { return wv }
        let wv = Tab.createWebView()
        wv.pageZoom = zoomLevel
        _webView = wv
        if let pendingReloadURL {
            self.pendingReloadURL = nil
            wv.load(URLRequest(url: pendingReloadURL))
        }
        return wv
    }

    /// Whether a WKWebView has been allocated for this tab.
    var hasWebView: Bool { _webView != nil }

    /// Lazy controllers backed by webView
    @ObservationIgnored private lazy var findController = FindInPageController(webView: webView)
    @ObservationIgnored private lazy var pipController = PictureInPictureController(webView: webView)
    @ObservationIgnored private let articleExtractionService = ArticleExtractionService()
    @ObservationIgnored private var originalDocumentHTML: String?
    @ObservationIgnored private var originalDocumentURL: URL?
    @ObservationIgnored private var originalDocumentTitle: String?
    @ObservationIgnored private var pendingReaderModeNavigation: ReaderModeInternalNavigation?
    @ObservationIgnored private var pendingReaderModeNavigationContinuation: CheckedContinuation<Void, Error>?

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
        let config = BrowserWebViewConfigurationFactory.shared.makeConfiguration(surface: .tab)
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

    // MARK: - Reader Mode

    func toggleReaderMode() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.setReaderModeEnabled(!self.isReaderMode)
        }
    }

    @MainActor
    func setReaderModeEnabled(_ enabled: Bool) async {
        guard !isChatTab, hasWebView else { return }

        isReaderMode = enabled

        guard !isLoading else { return }

        if enabled {
            _ = await applyReaderMode()
        } else {
            await disableReaderMode()
        }
    }

    @MainActor
    func handleReaderModeNavigationStarted() {
        guard pendingReaderModeNavigation == nil else { return }
        originalDocumentHTML = nil
        originalDocumentURL = nil
        originalDocumentTitle = nil
    }

    @MainActor
    func handleReaderModeNavigationFinished() async {
        guard pendingReaderModeNavigation == nil, isReaderMode, hasWebView else { return }
        _ = await applyReaderMode()
    }

    @MainActor
    @discardableResult
    func applyReaderMode() async -> Bool {
        guard hasWebView else { return false }
        let currentWebView = self.webView

        do {
            return try await ReaderModeTransitionAnimator.perform(in: currentWebView) { [self, currentWebView] in
                if self.originalDocumentHTML == nil {
                    self.originalDocumentHTML = try await currentWebView.evaluateJavaScript(
                        "document.documentElement.outerHTML"
                    ) as? String
                    self.originalDocumentURL = currentWebView.url
                    self.originalDocumentTitle = currentWebView.title
                }

                guard let originalDocumentHTML = self.originalDocumentHTML else {
                    return self.handleReaderModeFailure()
                }

                guard let article = try await self.articleExtractionService.extract(
                    from: originalDocumentHTML,
                    url: self.originalDocumentURL ?? currentWebView.url,
                    title: self.originalDocumentTitle ?? currentWebView.title
                ) else {
                    return self.handleReaderModeFailure()
                }

                let readerHTML = ReaderModeDocumentBuilder.document(for: article)
                try await self.loadReaderModeHTML(
                    readerHTML,
                    baseURL: self.originalDocumentURL ?? currentWebView.url,
                    navigation: .apply
                )
                self.title = article.title
                return true
            }
        } catch {
            Log.Browser.error("Reader mode extraction failed", error: error)
            clearPendingReaderModeNavigation()
            return handleReaderModeFailure()
        }
    }

    @MainActor
    func disableReaderMode() async {
        guard hasWebView else { return }
        let currentWebView = self.webView

        let originalDocumentHTML = originalDocumentHTML
        let restoredTitle = originalDocumentTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = restoredTitle?.isEmpty == false
            ? restoredTitle
            : originalDocumentURL?.host ?? currentWebView.url?.host ?? title
        let restoreBaseURL = originalDocumentURL ?? currentWebView.url

        self.originalDocumentHTML = nil
        self.originalDocumentURL = nil
        self.originalDocumentTitle = nil

        guard let originalDocumentHTML else {
            webView.reload()
            return
        }

        do {
            try await ReaderModeTransitionAnimator.perform(in: currentWebView) { [self] in
                try await self.loadReaderModeHTML(
                    originalDocumentHTML,
                    baseURL: restoreBaseURL,
                    navigation: .restore
                )
                if let fallbackTitle {
                    self.title = fallbackTitle
                }
            }
        } catch {
            Log.Browser.error("Reader mode restore failed", error: error)
            clearPendingReaderModeNavigation()
            currentWebView.reload()
        }
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

    func rebuildWebViewForConfigurationChange() {
        guard let webView = _webView else { return }

        pendingReloadURL = url ?? webView.url
        cleanup()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        _webView = nil
        webViewRevision = UUID()
    }

    deinit {
        cleanup()
    }

    @MainActor
    private func handleReaderModeFailure() -> Bool {
        clearPendingReaderModeNavigation()
        isReaderMode = false
        originalDocumentHTML = nil
        originalDocumentURL = nil
        originalDocumentTitle = nil
        return false
    }

    @MainActor
    func completePendingReaderModeNavigation(with result: Result<Void, Error>) -> Bool {
        guard pendingReaderModeNavigation != nil else { return false }

        pendingReaderModeNavigation = nil
        let continuation = pendingReaderModeNavigationContinuation
        pendingReaderModeNavigationContinuation = nil

        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }

        return true
    }

    @MainActor
    private func loadReaderModeHTML(
        _ html: String,
        baseURL: URL?,
        navigation: ReaderModeInternalNavigation
    ) async throws {
        guard pendingReaderModeNavigationContinuation == nil else {
            throw ReaderModeNavigationError.navigationAlreadyInProgress
        }

        pendingReaderModeNavigation = navigation

        try await withCheckedThrowingContinuation { continuation in
            pendingReaderModeNavigationContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    @MainActor
    private func clearPendingReaderModeNavigation() {
        pendingReaderModeNavigation = nil
        pendingReaderModeNavigationContinuation = nil
    }

    private enum ReaderModeInternalNavigation {
        case apply
        case restore
    }

    private enum ReaderModeNavigationError: Error {
        case navigationAlreadyInProgress
    }
}
