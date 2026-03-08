import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Mention suggestions")
struct MentionSuggestionsViewModelTests {
    @Test("Notes appear in chat mention suggestions")
    func suggestsNotes() async throws {
        OverlayWindowManager.shared.closeAll()

        let store = NoteStore(
            storageRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            saveDebounceInterval: .seconds(60)
        )
        store.bindToWorkspace(UUID())

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
                                    "text": "Quarterly roadmap",
                                ],
                            ],
                        ],
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Mention notes directly from chat.",
                                ],
                            ],
                        ],
                    ]),
                ]
            )
        )

        let viewModel = MentionSuggestionsViewModel()
        viewModel.noteStore = store
        viewModel.updateSuggestions(for: "roadmap", excluding: [], currentTabId: nil)

        try await Task.sleep(for: .milliseconds(120))

        #expect(
            viewModel.suggestions.contains {
                if case .note(let id, _, _) = $0.mention {
                    return id == note.id
                }
                return false
            }
        )
    }
}
