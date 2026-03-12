import Foundation
import Testing
@testable import WheelBrowser
import Fabric

@Suite("Chat Context Badge Tests")
struct ChatContextBadgeTests {

    @Test("Page contexts default to a website badge")
    func pageContextDefaultsToWebsiteBadge() {
        let context = PageContext(
            url: "https://www.mozilla.org/firefox/",
            title: "",
            textContent: "Firefox content"
        )

        #expect(context.contextBadge.kind == .website)
        #expect(context.contextBadge.title == "mozilla.org")
    }

    @Test("Badge dedupe preserves unique websites and collapses shared sources")
    func deduplicatesContextBadges() {
        let deduplicated = ChatContextBadge.deduplicated([
            .webSearch(resultsCount: 5),
            .webSearch(resultsCount: 5),
            .website(url: "https://example.com/a"),
            .website(url: "https://example.org/b")
        ])

        #expect(deduplicated.count == 3)
        #expect(deduplicated.map(\.id) == [
            "web-search",
            "website-https://example.com/a",
            "website-https://example.org/b"
        ])
    }

    @Test("Note badges preserve the note identity")
    func buildsNoteBadge() {
        let id = UUID()
        let badge = ChatContextBadge.note(id: id, title: "Planning")

        #expect(badge.kind == ChatContextBadge.Kind.note)
        #expect(badge.id == "note-\(id.uuidString)")
        #expect(badge.title == "Planning")
    }

    @Test("Generic Fabric badges preserve resource identity and hints")
    func buildsFabricResourceBadge() {
        let uri = FabricURI(appID: "external.docs", kind: "document", id: "roadmap")
        let badge = ChatContextBadge.fabricResource(
            uri: uri,
            title: "Platform Roadmap",
            detail: "Q3 planning document",
            presentation: .init(
                systemImage: "doc.richtext",
                tint: "gray",
                subtitle: "Q3 planning document",
                categoryLabel: "Document"
            )
        )

        #expect(badge.kind == .fabricResource)
        #expect(badge.resourceURI == uri)
        #expect(badge.presentation?.systemImage == "doc.richtext")
        #expect(badge.presentation?.categoryLabel == "Document")
    }
}
