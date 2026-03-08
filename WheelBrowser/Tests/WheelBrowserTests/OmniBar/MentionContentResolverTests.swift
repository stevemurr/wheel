import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Mention content resolver")
struct MentionContentResolverTests {
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
            noteStore: store
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
