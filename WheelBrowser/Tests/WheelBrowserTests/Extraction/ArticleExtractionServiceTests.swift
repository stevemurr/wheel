import Foundation
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

    @Test("Structured extraction preserves paragraph boundaries for chunking")
    func preservesParagraphBoundaries() async throws {
        let html = """
        <html>
          <body>
            <article>
              <h1>Structured Article</h1>
              <p>\(String(repeating: "First paragraph discusses swift programming code and application architecture. ", count: 8))</p>
              <p>\(String(repeating: "Second paragraph expands on testing strategy, deployment safety, and code review discipline. ", count: 8))</p>
              <h2>Project Details</h2>
              <p>\(String(repeating: "Third paragraph covers documentation, observability, and maintenance workflows. ", count: 8))</p>
            </article>
          </body>
        </html>
        """

        let result = try #require(
            try await service.extract(from: html, url: URL(string: "https://example.com/structured"), title: nil)
        )

        #expect(result.textContent.contains("\n\n"))
        let chunks = TextChunker.chunk(text: result.textContent)
        #expect(chunks.count >= 2)
        #expect(chunks.contains { $0.sectionHierarchy.contains("Project Details") })
    }
}
