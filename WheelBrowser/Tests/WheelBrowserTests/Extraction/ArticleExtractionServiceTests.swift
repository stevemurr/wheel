import Testing
@testable import WheelBrowser

@Suite("ArticleExtractionService", .serialized)
struct ArticleExtractionServiceTests {
    private let service = ArticleExtractionService()

    @Test("Extracts readable article content from article fixture")
    func extractsArticleFixture() async throws {
        let html = try ExtractionFixture.html(named: "article")
        let result = try #require(
            try await service.extract(from: html, url: ExtractionFixture.url(named: "article"), title: nil)
        )

        #expect(result.title == "Wheel Launches Reader Mode")
        #expect(result.textContent.contains("Reader mode cuts away repeated navigation"))
        #expect(result.contentHTML.contains("<p>"))
    }

    @Test("Extracts documentation pages without dropping code blocks")
    func extractsDocsFixture() async throws {
        let html = try ExtractionFixture.html(named: "docs")
        let result = try #require(
            try await service.extract(from: html, url: ExtractionFixture.url(named: "docs"), title: nil)
        )

        #expect(result.title == "Reader Mode API Guide")
        #expect(result.textContent.contains("shared extraction service"))
        #expect(result.contentHTML.contains("<pre"))
    }

    @Test("Extracts article text from app-shell fixture")
    func extractsSPAFixture() async throws {
        let html = try ExtractionFixture.html(named: "spa")
        let result = try #require(
            try await service.extract(from: html, url: ExtractionFixture.url(named: "spa"), title: nil)
        )

        #expect(result.title == "Market Recap")
        #expect(result.textContent.contains("afternoon market recap"))
    }

    @Test("Falls back to plain text for non-article landing pages")
    func fallsBackForLandingPage() async throws {
        let html = try ExtractionFixture.html(named: "landing")
        let result = try #require(
            try await service.extract(from: html, url: ExtractionFixture.url(named: "landing"), title: nil)
        )

        #expect(result.title == "Welcome to Wheel")
        #expect(!result.textContent.isEmpty)
        #expect(result.textContent.contains("Overlay browsing"))
    }
}
