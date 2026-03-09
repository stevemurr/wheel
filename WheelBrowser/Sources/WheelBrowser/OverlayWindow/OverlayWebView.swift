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
        let hostSpec = context.coordinator.makeHostSpec(initialURL: url)
        context.coordinator.hostSpec = hostSpec
        return WKWebViewHost.build(spec: hostSpec)
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

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        guard let hostSpec = coordinator.hostSpec else { return }
        WKWebViewHost.dismantle(nsView, spec: hostSpec)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let item: OverlayWindowItem
        @Binding var isLoading: Bool
        @Binding var isReaderMode: Bool
        var hostSpec: HostedWKWebViewSpec?
        var lastReaderModeState: Bool = false
        private let articleExtractionService = ArticleExtractionService()
        private var originalDocumentHTML: String?
        private var originalDocumentURL: URL?
        private var originalDocumentTitle: String?
        private var pendingReaderModeNavigation: ReaderModeInternalNavigation?
        private var pendingReaderModeNavigationContinuation: CheckedContinuation<Void, Error>?

        init(item: OverlayWindowItem, isLoading: Binding<Bool>, isReaderMode: Binding<Bool>) {
            self.item = item
            self._isLoading = isLoading
            self._isReaderMode = isReaderMode
        }

        func makeHostSpec(initialURL: URL) -> HostedWKWebViewSpec {
            HostedWKWebViewSpec(
                makeConfiguration: {
                    BrowserWebViewConfigurationFactory.shared.makeConfiguration(surface: .overlay)
                },
                configure: { [weak self] webView in
                    guard let self else { return }
                    webView.allowsBackForwardNavigationGestures = true
                    webView.navigationDelegate = self
                    webView.uiDelegate = self
                },
                initialLoad: .request(URLRequest(url: initialURL)),
                teardown: { webView in
                    webView.navigationDelegate = nil
                    webView.uiDelegate = nil
                }
            )
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.isLoading = true
                if !self.isReaderMode {
                    self.originalDocumentHTML = nil
                    self.originalDocumentURL = nil
                    self.originalDocumentTitle = nil
                }
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

                if self.completePendingReaderModeNavigation(with: .success(())) {
                    return
                }

                if self.isReaderMode {
                    _ = await self.applyReaderMode(in: webView)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                if self.completePendingReaderModeNavigation(with: .failure(error)) {
                    self.isLoading = false
                    return
                }
                self.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                if self.completePendingReaderModeNavigation(with: .failure(error)) {
                    self.isLoading = false
                    return
                }
                self.isLoading = false
            }
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            WebViewUIDelegateSupport.presentAlert(message: message, completionHandler: completionHandler)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            WebViewUIDelegateSupport.presentConfirmation(message: message, completionHandler: completionHandler)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            WebViewUIDelegateSupport.handlePopup(in: webView, navigationAction: navigationAction)
        }

        // MARK: - Reader Mode

        func enableReaderMode(in webView: WKWebView) {
            Task { @MainActor in
                _ = await applyReaderMode(in: webView)
            }
        }

        func disableReaderMode(in webView: WKWebView) {
            if let originalDocumentHTML {
                let restoredTitle = originalDocumentTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackTitle = restoredTitle?.isEmpty == false
                    ? restoredTitle
                    : originalDocumentURL?.host ?? webView.url?.host ?? item.title
                let restoreBaseURL = self.originalDocumentURL ?? webView.url

                self.originalDocumentHTML = nil
                self.originalDocumentURL = nil
                self.originalDocumentTitle = nil

                Task { @MainActor in
                    do {
                        try await ReaderModeTransitionAnimator.perform(in: webView) { [self, webView] in
                            try await self.loadReaderModeHTML(
                                originalDocumentHTML,
                                baseURL: restoreBaseURL,
                                navigation: .restore,
                                in: webView
                            )
                            if let fallbackTitle {
                                self.item.title = fallbackTitle
                            }
                        }
                    } catch {
                        Log.Overlay.error("Reader mode restore failed", error: error)
                        self.clearPendingReaderModeNavigation()
                        webView.reload()
                    }
                }
                return
            }

            webView.reload()
        }

        @MainActor
        func applyReaderMode(in webView: WKWebView) async -> Bool {
            do {
                return try await ReaderModeTransitionAnimator.perform(in: webView) { [self, webView] in
                    if self.originalDocumentHTML == nil {
                        self.originalDocumentHTML = try await webView.evaluateJavaScript(
                            "document.documentElement.outerHTML"
                        ) as? String
                        self.originalDocumentURL = webView.url
                        self.originalDocumentTitle = webView.title
                    }

                    guard let originalDocumentHTML = self.originalDocumentHTML else {
                        self.isReaderMode = false
                        self.lastReaderModeState = false
                        self.originalDocumentHTML = nil
                        self.originalDocumentURL = nil
                        self.originalDocumentTitle = nil
                        return false
                    }

                    guard let article = try await self.articleExtractionService.extract(
                        from: originalDocumentHTML,
                        url: self.originalDocumentURL ?? webView.url,
                        title: self.originalDocumentTitle ?? webView.title
                    ) else {
                        self.isReaderMode = false
                        self.lastReaderModeState = false
                        self.originalDocumentHTML = nil
                        self.originalDocumentURL = nil
                        self.originalDocumentTitle = nil
                        return false
                    }

                    let readerHTML = ReaderModeDocumentBuilder.document(for: article)
                    try await self.loadReaderModeHTML(
                        readerHTML,
                        baseURL: self.originalDocumentURL ?? webView.url,
                        navigation: .apply,
                        in: webView
                    )
                    self.item.title = article.title
                    return true
                }
            } catch {
                Log.Overlay.error("Reader mode extraction failed", error: error)
                clearPendingReaderModeNavigation()
                isReaderMode = false
                lastReaderModeState = false
                originalDocumentHTML = nil
                originalDocumentURL = nil
                originalDocumentTitle = nil
                return false
            }
        }

        @MainActor
        private func completePendingReaderModeNavigation(with result: Result<Void, Error>) -> Bool {
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
            navigation: ReaderModeInternalNavigation,
            in webView: WKWebView
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
}
