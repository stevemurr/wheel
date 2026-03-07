import Foundation
import Foundation
import Testing
@testable import WheelBrowser

@Suite("ContentExtractor")
struct ContentExtractorTests {
    @MainActor
    @Test("Shared extractor truncates long page content for page context")
    func truncatesLongContent() async throws {
        let repeatedParagraph = String(
            repeating: "Reader mode keeps article content readable while removing duplicated navigation and preserving headings, links, code blocks, images, and article structure for downstream indexing and agent use. ",
            count: 240
        )
        let html = """
        <html>
        <head><title>Long Article</title></head>
        <body>
            <article>
                <h1>Long Article</h1>
                <p>\(repeatedParagraph)</p>
            </article>
        </body>
        </html>
        """

        let extractor = ContentExtractor()
        let context = try #require(
            await extractor.extractContent(
                from: html,
                url: URL(string: "https://example.com/long-article"),
                title: "Long Article"
            )
        )

        #expect(context.title == "Long Article")
        #expect(context.textContent.count <= 4003)
        #expect(context.textContent.count < repeatedParagraph.count)
    }

    @Test("Semantic indexing uses shared readability-backed extraction")
    func semanticIndexingUsesSharedExtraction() async throws {
        let html = try ExtractionFixture.html(named: "docs")
        let content = try #require(
            await SemanticIndexingHandler.extractIndexableContent(
                from: html,
                url: ExtractionFixture.url(named: "docs"),
                title: "Reader Mode API Guide"
            )
        )

        #expect(content.contains("web view"))
        #expect(content.contains("cleaned article HTML"))
    }
}
