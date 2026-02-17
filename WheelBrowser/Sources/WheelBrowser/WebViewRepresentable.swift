import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView updates handled by Tab
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let tab: Tab

        init(tab: Tab) {
            self.tab = tab
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
                self.tab.title = webView.title ?? "Untitled"
                self.tab.url = webView.url
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward

                // Record page load for blocking stats
                if AppSettings.shared.adBlockingEnabled {
                    ContentBlockerManager.shared.recordPageLoad()
                }

                // Record to browsing history with current workspace
                if let url = webView.url {
                    let title = webView.title ?? "Untitled"
                    let workspaceID = WorkspaceManager.shared.currentWorkspaceID
                    BrowsingHistory.shared.addEntry(url: url, title: title, workspaceID: workspaceID)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
        }
    }
}
