import SwiftUI
import WebKit

struct NoteEditorView: NSViewRepresentable {
    let bridge: NoteEditorBridge

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(bridge, name: "noteEditorBridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        bridge.attach(to: webView)

        if let editorURL = NoteEditorResources.editorHTMLURL(),
           let directoryURL = NoteEditorResources.editorDirectoryURL() {
            webView.loadFileURL(editorURL, allowingReadAccessTo: directoryURL)
        } else {
            webView.loadHTMLString(
                """
                <html>
                  <body style="font-family: -apple-system; padding: 16px;">
                    Note editor resources are missing. Build the note editor bundle to enable editing.
                  </body>
                </html>
                """,
                baseURL: nil
            )
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "noteEditorBridge")
    }
}
