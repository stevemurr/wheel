import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        tab.webView.uiDelegate = context.coordinator

        // Register link hover message handler
        let contentController = tab.webView.configuration.userContentController
        contentController.add(context.coordinator, name: "linkHover")
        contentController.add(context.coordinator, name: "overlayWindow")

        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView updates handled by Tab
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        // Unregister message handlers to break retain cycles
        let contentController = nsView.configuration.userContentController
        contentController.removeScriptMessageHandler(forName: "linkHover")
        contentController.removeScriptMessageHandler(forName: "overlayWindow")

        // Clear delegates to break retain cycles
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let tab: Tab
        private let navigationPolicyHandler = NavigationPolicyHandler()
        private let downloadHandler = DownloadHandler()
        private lazy var pageLifecycleHandler = PageLifecycleHandler(tab: tab)

        init(tab: Tab) {
            self.tab = tab
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
                self.pageLifecycleHandler.didFinish(navigation: navigation, webView: webView) { webView, url, title, workspaceID in
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
            let alert = NSAlert()
            alert.messageText = "Alert"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Confirm"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle popup windows for OAuth flows
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
