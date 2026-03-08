import Foundation
import Testing
import WebKit
@testable import WheelBrowser

@Suite("Note editor resources", .serialized)
@MainActor
struct NoteEditorResourceTests {
    @Test("Bundled editor HTML is present and bootstraps the runtime")
    func loadsEditorBundle() async throws {
        let webView = try await makeLoadedWebView()

        let result = try await webView.evaluateJavaScript("typeof window.NoteEditor.receiveCommand === 'function'")
        let hasBridge = try #require(result as? Bool)
        #expect(hasBridge)
    }

    @Test("Bundled editor exposes an explicit remove control for page source cards")
    func pageSourceCardsCanBeRemoved() async throws {
        let webView = try await makeLoadedWebView()

        let sourceCountBefore = try await webView.evaluateJavaScript(
            """
            (() => {
              window.NoteEditor.receiveCommand('loadDocument', {
                document: {
                  type: 'doc',
                  content: [
                    {
                      type: 'pageSource',
                      attrs: {
                        title: 'Wheel Docs',
                        url: 'https://example.com/docs',
                        capturedAt: '2026-03-08T00:00:00Z'
                      }
                    },
                    { type: 'paragraph' }
                  ]
                }
              });

              return document.querySelectorAll('.page-source__remove').length;
            })()
            """
        )
        #expect((sourceCountBefore as? NSNumber)?.intValue == 1)

        let sourceCountAfter = try await webView.evaluateJavaScript(
            """
            (() => {
              const button = document.querySelector('.page-source__remove');
              button?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
              return document.querySelectorAll('.page-source').length;
            })()
            """
        )
        #expect((sourceCountAfter as? NSNumber)?.intValue == 0)
    }

    @Test("Bundled editor applies markdown heading shortcuts")
    func markdownShortcutsTransformContent() async throws {
        let webView = try await makeLoadedWebView()

        let applied = try await webView.evaluateJavaScript(
            "window.NoteEditor.debugApplyMarkdown('# ').applied"
        )
        let nodeType = try await webView.evaluateJavaScript(
            "window.NoteEditor.debugApplyMarkdown('# ').type"
        )
        let headingLevel = try await webView.evaluateJavaScript(
            "window.NoteEditor.debugApplyMarkdown('# ').level"
        )

        #expect(applied as? Bool == true)
        #expect(nodeType as? String == "heading")
        #expect((headingLevel as? NSNumber)?.intValue == 1)
    }

    private func makeLoadedWebView() async throws -> WKWebView {
        let htmlURL = try #require(NoteEditorResources.editorHTMLURL())
        let directoryURL = try #require(NoteEditorResources.editorDirectoryURL())
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
        try await delegate.waitUntilLoaded()
        return webView
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
