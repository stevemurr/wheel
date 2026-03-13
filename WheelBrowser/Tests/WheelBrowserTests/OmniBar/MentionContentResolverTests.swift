import Fabric
import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Mention content resolver")
struct MentionContentResolverTests {
    @Test("Current page mentions resolve locally without Fabric round-trips")
    func currentPageMentionsDoNotCallFabric() async {
        let fabricClient = FabricMentionClientStub()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: fabricClient,
            fabricResolutionTimeout: .seconds(1)
        )

        let contexts = await resolver.resolve(
            mentions: [.currentPage],
            query: "page"
        )

        #expect(contexts.isEmpty)
        #expect(fabricClient.resolveCallCount == 0)
    }

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
            ),
            fabricResolutionTimeout: .seconds(1)
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

    @Test("Page snapshot mentions fall back to local metadata when no snapshot bridge is available")
    func fallsBackForPageSnapshotMentionsWithoutSnapshotBridge() async {
        let tabID = UUID()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: FabricMentionClientStub(),
            fabricResolutionTimeout: .seconds(1)
        )

        let contexts = await resolver.resolve(
            mentions: [.pageSnapshot(id: tabID, title: "Checkout flow", url: "https://example.com/checkout")],
            query: "snapshot"
        )

        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .website)
        #expect(contexts.first?.title == "Checkout flow")
        #expect(contexts.first?.textContent == """
        [Page Snapshot]
        Title: Checkout flow
        URL: https://example.com/checkout
        """)
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
            ),
            fabricResolutionTimeout: .seconds(1)
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
            fabricClient: nil,
            fabricResolutionTimeout: .seconds(1)
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

    @Test("Timed-out Fabric note lookups fall back to title-only note context")
    func timesOutFabricLookupsWithoutBlockingFallbacks() async {
        let noteID = UUID()
        let fabricClient = FabricMentionClientStub(
            resolveDelay: .seconds(5)
        )
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            fabricClient: fabricClient,
            fabricResolutionTimeout: .milliseconds(10)
        )

        let contexts = await resolver.resolve(
            mentions: [.note(id: noteID, title: "Architecture notes", excerpt: "")],
            query: "architecture"
        )

        #expect(fabricClient.resolveCallCount == 1)
        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .note)
        #expect(contexts.first?.textContent == "[From Note]\nArchitecture notes")
    }
}
