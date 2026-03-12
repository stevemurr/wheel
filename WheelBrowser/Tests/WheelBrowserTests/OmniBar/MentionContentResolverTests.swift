import Fabric
import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Mention content resolver")
struct MentionContentResolverTests {
    @Test("Page snapshot mentions resolve through Fabric when available")
    func resolvesFabricPageSnapshotMentions() async {
        let tabID = UUID()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            noteStore: NoteStore(
                storageRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
                saveDebounceInterval: .seconds(60)
            ),
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
        let store = NoteStore(
            storageRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            saveDebounceInterval: .seconds(60)
        )
        store.bindToWorkspace(UUID())

        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: BrowserState(),
            currentTab: Tab(),
            noteStore: store,
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

    @Test("Note mentions resolve into note-backed chat context")
    func resolvesNoteMentions() async {
        let store = NoteStore(
            storageRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            saveDebounceInterval: .seconds(60)
        )
        let workspaceID = UUID()
        store.bindToWorkspace(workspaceID)

        let note = store.createNote()
        store.updateDocument(
            id: note.id,
            document: NoteDocument(
                root: [
                    "type": AnyCodable("doc"),
                    "content": AnyCodable([
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Architecture notes",
                                ],
                            ],
                        ],
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Capture note mentions in AI chat.",
                                ],
                            ],
                        ],
                    ]),
                ]
            )
        )

        let browserState = BrowserState()
        let resolver = MentionContentResolver(
            contentExtractor: ContentExtractor(),
            browserState: browserState,
            currentTab: Tab(),
            noteStore: store,
            fabricClient: nil
        )

        let contexts = await resolver.resolve(
            mentions: [.note(id: note.id, title: "Architecture notes", excerpt: "Capture note mentions in AI chat.")],
            query: "architecture"
        )

        #expect(contexts.count == 1)
        #expect(contexts.first?.contextBadge.kind == .note)
        #expect(contexts.first?.title == "Architecture notes")
        #expect(contexts.first?.textContent.contains("Capture note mentions in AI chat.") == true)
    }
}
