import SwiftUI
import Testing
import WebKit
@testable import WheelBrowser

@Suite("Overlay reader mode", .serialized)
struct OverlayWebViewReaderModeTests {
    @MainActor
    @Test("Reader mode renders extracted article content in place")
    func rendersReadableArticle() async throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let fileURL = try await loadFixture(named: "article", in: webView)

        let state = ReaderModeBindingState()
        state.isReaderMode = true
        let coordinator = makeCoordinator(state: state, url: fileURL)

        let success = await coordinator.applyReaderMode(in: webView)
        #expect(success)

        let title = try #require(try await webView.evaluateJavaScript("document.title") as? String)
        let bodyHTML = try #require(try await webView.evaluateJavaScript("document.body.innerHTML") as? String)

        #expect(title == "Wheel Launches Reader Mode")
        #expect(bodyHTML.contains("reader-container"))
        #expect(bodyHTML.contains("Reader mode cuts away repeated navigation"))
    }

    @MainActor
    @Test("Disabling reader mode restores the original page content")
    func restoresOriginalPage() async throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let fileURL = try await loadFixture(named: "spa", in: webView)

        let state = ReaderModeBindingState()
        state.isReaderMode = true
        let coordinator = makeCoordinator(state: state, url: fileURL)

        #expect(await coordinator.applyReaderMode(in: webView))
        coordinator.disableReaderMode(in: webView)
        try await waitUntilJavaScript(in: webView, script: "document.body.innerText.includes('Trending tickers')")

        let restoredBody = try #require(try await webView.evaluateJavaScript("document.body.innerText") as? String)
        #expect(restoredBody.contains("Trending tickers"))
        #expect(restoredBody.contains("Market Recap"))
    }

    @MainActor
    @Test("Reader mode failure leaves the page intact and resets toggle state")
    func failureLeavesPageIntact() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head></head>
        <body></body>
        </html>
        """
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        try await loadHTML(html, baseURL: URL(string: "https://example.com/blank")!, in: webView)

        let state = ReaderModeBindingState()
        state.isReaderMode = true
        let coordinator = makeCoordinator(state: state, url: URL(string: "https://example.com/blank")!)

        let success = await coordinator.applyReaderMode(in: webView)
        let bodyText = try #require(try await webView.evaluateJavaScript("document.body.innerText") as? String)

        #expect(!success)
        #expect(!state.isReaderMode)
        #expect(bodyText.isEmpty)
    }

    @MainActor
    private func makeCoordinator(state: ReaderModeBindingState, url: URL) -> OverlayWebView.Coordinator {
        let isLoading = Binding(
            get: { state.isLoading },
            set: { state.isLoading = $0 }
        )
        let isReaderMode = Binding(
            get: { state.isReaderMode },
            set: { state.isReaderMode = $0 }
        )
        let item = OverlayWindowItem(
            url: url,
            title: url.host ?? url.absoluteString,
            position: .zero,
            size: CGSize(width: 800, height: 600),
            zIndex: 0
        )

        return OverlayWebView.Coordinator(
            item: item,
            isLoading: isLoading,
            isReaderMode: isReaderMode
        )
    }
}
