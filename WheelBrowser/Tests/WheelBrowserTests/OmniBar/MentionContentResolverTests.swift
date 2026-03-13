import Fabric
import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Mention content resolver")
struct MentionContentResolverTests {
    @Test("Generic Fabric mentions resolve into generic chat context badges")
    func resolvesGenericFabricMentions() async {
        let resourceURI = FabricURI(appID: "external.docs", kind: "document", id: "roadmap")
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: FabricMentionClientStub(
                contexts: [
                    FabricContextPayload(
                        uri: resourceURI,
                        kind: "document",
                        title: "Platform Roadmap",
                        body: "Ship generic Fabric mentions for future apps.",
                        presentation: .init(
                            systemImage: "doc.richtext",
                            tint: "gray",
                            subtitle: "Q3 planning document",
                            categoryLabel: "Document"
                        )
                    )
                ]
            )
        )

        let contexts = await resolver.resolve(
            mentions: [
                .fabricResource(
                    FabricMentionReference(
                        uri: resourceURI,
                        kind: "document",
                        title: "Platform Roadmap",
                        summary: "Q3 planning document",
                        url: nil,
                        presentation: .init(
                            systemImage: "doc.richtext",
                            tint: "gray",
                            subtitle: "Q3 planning document",
                            categoryLabel: "Document"
                        )
                    )
                )
            ],
            query: "roadmap"
        )

        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .fabricResource)
        #expect(contexts.first?.contextBadge.resourceURI == resourceURI)
        #expect(contexts.first?.textContent.contains("Ship generic Fabric mentions for future apps.") == true)
    }

    @Test("Page snapshot mentions resolve through Fabric when available")
    func resolvesFabricPageSnapshotMentions() async {
        let tabID = UUID()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: FabricMentionClientStub(
                contexts: [
                    FabricContextPayload(
                        uri: FabricURI(appID: WheelFabricAppID.browser, kind: "page-snapshot", id: tabID.uuidString),
                        kind: "page-snapshot",
                        title: "Checkout flow",
                        body: "Snapshot content for the checkout page.",
                        metadata: [
                            "url": .string("https://example.com/checkout")
                        ]
                    )
                ]
            )
        )

        let contexts = await resolver.resolve(
            mentions: [.pageSnapshot(id: tabID, title: "Checkout flow", url: "https://example.com/checkout")],
            query: "snapshot"
        )

        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .website)
        #expect(contexts.first?.title == "Checkout flow")
        #expect(contexts.first?.textContent.contains("Snapshot content for the checkout page.") == true)
    }

    @Test("Note mentions resolve through Fabric when available")
    func resolvesFabricNoteMentions() async {
        let noteID = UUID()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: FabricMentionClientStub(
                contexts: [
                    FabricContextPayload(
                        uri: FabricURI(appID: WheelFabricAppID.notes, kind: "note", id: noteID.uuidString),
                        kind: "note",
                        title: "Architecture notes",
                        body: "Capture note mentions in AI chat."
                    )
                ]
            )
        )

        let contexts = await resolver.resolve(
            mentions: [.note(id: noteID, title: "Architecture notes", excerpt: "")],
            query: "architecture"
        )

        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .note)
        #expect(contexts.first?.title == "Architecture notes")
        #expect(contexts.first?.textContent.contains("Capture note mentions in AI chat.") == true)
    }

    @Test("Note mentions fall back to title-only context when Fabric is unavailable")
    func fallsBackForNoteMentionsWithoutFabric() async {
        let noteID = UUID()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: nil
        )

        let contexts = await resolver.resolve(
            mentions: [.note(id: noteID, title: "Architecture notes", excerpt: "Capture note mentions in AI chat.")],
            query: "architecture"
        )

        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .note)
        #expect(contexts.first?.title == "Architecture notes")
        #expect(contexts.first?.textContent == "[From Note]\nArchitecture notes")
    }
}
