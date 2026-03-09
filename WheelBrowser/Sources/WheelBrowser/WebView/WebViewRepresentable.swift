import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let tab: Tab
    let isActive: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = tab.webView
        let hostSpec = context.coordinator.makeHostSpec()
        context.coordinator.hostSpec = hostSpec
        WKWebViewHost.attach(webView, spec: hostSpec)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.isHidden = !isActive
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        guard let hostSpec = coordinator.hostSpec else { return }
        WKWebViewHost.dismantle(nsView, spec: hostSpec)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let tab: Tab
        var hostSpec: HostedWKWebViewSpec?
        private let navigationPolicyHandler = NavigationPolicyHandler()
        private let downloadHandler = DownloadHandler()
        private lazy var pageLifecycleHandler = PageLifecycleHandler(tab: tab)

        init(tab: Tab) {
            self.tab = tab
        }

        func makeHostSpec() -> HostedWKWebViewSpec {
            HostedWKWebViewSpec(
                scriptMessageHandlers: [
                    .init(name: "linkHover", handler: self),
                    .init(name: "overlayWindow", handler: self),
                ],
                configure: { [weak self] webView in
                    guard let self else { return }
                    webView.navigationDelegate = self
                    webView.uiDelegate = self
                },
                teardown: { webView in
                    webView.navigationDelegate = nil
                    webView.uiDelegate = nil
                }
            )
        }

        // MARK: - WKScriptMessageHandler (delegated to ScriptMessageHandler)

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            ScriptMessageHandler.handle(message)
        }

        // MARK: - WKNavigationDelegate (delegated to PageLifecycleHandler)

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.pageLifecycleHandler.didStartProvisionalNavigation()
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                self.pageLifecycleHandler.didCommit(navigation: navigation, webView: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                await self.pageLifecycleHandler.didFinish(navigation: navigation, webView: webView) { webView, url, title, workspaceID in
                    SemanticIndexingHandler.indexPage(webView: webView, url: url, title: title, workspaceID: workspaceID)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.pageLifecycleHandler.handleNavigationError(error, isProvisional: false)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.pageLifecycleHandler.handleNavigationError(error, isProvisional: true)
            }
        }

        // MARK: - Navigation Policy (delegated to NavigationPolicyHandler)

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            if navigationAction.targetFrame?.isMainFrame != false,
               let requestURL = navigationAction.request.url {
                tab.url = requestURL
            }
            navigationPolicyHandler.decidePolicy(for: navigationAction, preferences: preferences, decisionHandler: decisionHandler)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            navigationPolicyHandler.decidePolicy(for: navigationResponse, decisionHandler: decisionHandler)
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = downloadHandler
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = downloadHandler
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
    }
}
