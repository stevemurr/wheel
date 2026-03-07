import Testing
import WebKit
@testable import WheelBrowser

@Suite("Tab reader mode", .serialized)
struct TabReaderModeTests {
    @MainActor
    @Test("Reader mode renders extracted article content in a regular tab")
    func rendersReadableArticle() async throws {
        let tab = Tab()
        _ = try await loadFixture(named: "article", in: tab.webView)

        await tab.setReaderModeEnabled(true)

        let title = try #require(try await tab.webView.evaluateJavaScript("document.title") as? String)
        let bodyHTML = try #require(try await tab.webView.evaluateJavaScript("document.body.innerHTML") as? String)

        #expect(tab.isReaderMode)
        #expect(title == "Wheel Launches Reader Mode")
        #expect(bodyHTML.contains("reader-container"))
        #expect(bodyHTML.contains("Reader mode cuts away repeated navigation"))
    }

    @MainActor
    @Test("Disabling reader mode restores the original tab content")
    func restoresOriginalPage() async throws {
        let tab = Tab()
        _ = try await loadFixture(named: "spa", in: tab.webView)

        await tab.setReaderModeEnabled(true)
        await tab.setReaderModeEnabled(false)

        let restoredBody = try #require(try await tab.webView.evaluateJavaScript("document.body.innerText") as? String)

        #expect(!tab.isReaderMode)
        #expect(restoredBody.contains("Trending tickers"))
        #expect(restoredBody.contains("Market Recap"))
    }

    @MainActor
    @Test("Reader mode follows regular tab navigation without restoring the previous page")
    func followsNavigation() async throws {
        let tab = Tab()
        _ = try await loadFixture(named: "article", in: tab.webView)

        await tab.setReaderModeEnabled(true)

        tab.handleReaderModeNavigationStarted()
        _ = try await loadFixture(named: "docs", in: tab.webView)
        await tab.handleReaderModeNavigationFinished()

        let readerBody = try #require(try await tab.webView.evaluateJavaScript("document.body.innerText") as? String)
        #expect(readerBody.contains("Reader Mode API Guide"))

        await tab.setReaderModeEnabled(false)

        let restoredBody = try #require(try await tab.webView.evaluateJavaScript("document.body.innerText") as? String)
        #expect(restoredBody.contains("The reader mode API exposes one shared extraction service"))
        #expect(!restoredBody.contains("Wheel has added a reader mode"))
    }
}
