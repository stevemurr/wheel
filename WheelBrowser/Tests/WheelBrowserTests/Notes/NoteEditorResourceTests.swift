import Foundation
import Testing
import WebKit
@testable import WheelBrowser

@Suite("Note editor resources", .serialized)
@MainActor
struct NoteEditorResourceTests {
    @Test("Bundled editor HTML is present and bootstraps the runtime")
    func loadsEditorBundle() async throws {
        let htmlURL = try #require(NoteEditorResources.editorHTMLURL())
        let directoryURL = try #require(NoteEditorResources.editorDirectoryURL())
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
        try await delegate.waitUntilLoaded()

        let result = try await webView.evaluateJavaScript("typeof window.NoteEditor.receiveCommand === 'function'")
        let hasBridge = try #require(result as? Bool)
        #expect(hasBridge)
    }
}

@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitUntilLoaded() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
