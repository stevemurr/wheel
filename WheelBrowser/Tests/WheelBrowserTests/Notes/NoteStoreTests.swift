import Foundation
import Testing
@testable import WheelBrowser

@Suite("NoteStore", .serialized)
@MainActor
struct NoteStoreTests {
    @Test("Creating notes yields distinct records")
    func createsDistinctNotes() {
        let store = makeStore()
        let workspaceID = UUID()
        store.bindToWorkspace(workspaceID)

        let first = store.createNote(title: "First")
        let second = store.createNote(title: "Second")

        #expect(first.id != second.id)
        #expect(store.notes.count == 2)
    }

    @Test("Notes persist and reload")
    func persistsAndReloadsNotes() throws {
        let root = tempDirectory()
        let workspaceID = UUID()

        let store = NoteStore(storageRoot: root, saveDebounceInterval: .seconds(60))
        store.bindToWorkspace(workspaceID)
        let first = store.createNote(title: "Ideas")
        let second = store.createNote(title: "Research")
        store.updateDocument(
            id: second.id,
            document: NoteDocument(
                root: [
                    "type": AnyCodable("doc"),
                    "content": AnyCodable([
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Track launch notes",
                                ],
                            ],
                        ],
                    ]),
                ]
            )
        )
        store.flushPendingSaves()

        let reloaded = NoteStore(storageRoot: root, saveDebounceInterval: .seconds(60))
        reloaded.bindToWorkspace(workspaceID)

        #expect(reloaded.notes.count == 2)
        #expect(reloaded.note(with: first.id) != nil)
        let savedSecond = try #require(reloaded.note(with: second.id))
        #expect(savedSecond.excerpt.contains("Track launch notes"))
    }

    @Test("Workspace binding isolates note collections")
    func isolatesWorkspaces() {
        let store = makeStore()
        let workspaceA = UUID()
        let workspaceB = UUID()

        store.bindToWorkspace(workspaceA)
        let noteA = store.createNote(title: "A")
        store.flushPendingSaves()

        store.bindToWorkspace(workspaceB)
        _ = store.createNote(title: "B")
        store.flushPendingSaves()

        store.bindToWorkspace(workspaceA)

        #expect(store.notes.count == 1)
        #expect(store.notes.first?.id == noteA.id)
    }

    @Test("Source insertion updates excerpt and persists")
    func insertsPageSource() throws {
        let root = tempDirectory()
        let store = NoteStore(storageRoot: root, saveDebounceInterval: .seconds(60))
        let workspaceID = UUID()
        store.bindToWorkspace(workspaceID)
        let note = store.createNote(title: "Research")

        store.insertPageSource(
            id: note.id,
            source: NotePageSource(title: "Wheel Docs", url: "https://example.com/docs")
        )
        store.flushPendingSaves()

        let reloaded = NoteStore(storageRoot: root, saveDebounceInterval: .seconds(60))
        reloaded.bindToWorkspace(workspaceID)

        let updated = try #require(reloaded.note(with: note.id))
        #expect(updated.excerpt.contains("Wheel Docs"))
        #expect(updated.excerpt.contains("https://example.com/docs"))
    }

    @Test("Ordered notes prioritize the most recently updated note")
    func ordersNotesByRecentActivity() {
        let store = makeStore()
        let workspaceID = UUID()
        store.bindToWorkspace(workspaceID)

        let older = store.createNote(title: "Older")
        let newer = store.createNote(title: "Newer")
        store.updateDocument(
            id: older.id,
            document: NoteDocument(
                root: [
                    "type": AnyCodable("doc"),
                    "content": AnyCodable([
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Fresh note",
                                ],
                            ],
                        ],
                    ]),
                ]
            )
        )

        let ordered = store.orderedNotes
        #expect(ordered.first?.id == older.id)
        #expect(ordered.contains { $0.id == newer.id })
    }

    private func makeStore() -> NoteStore {
        NoteStore(storageRoot: tempDirectory(), saveDebounceInterval: .seconds(60))
    }

    private func tempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
