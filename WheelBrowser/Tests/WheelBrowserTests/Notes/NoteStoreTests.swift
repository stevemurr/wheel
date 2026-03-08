import Foundation
import Testing
@testable import WheelBrowser

@Suite("NoteStore", .serialized)
@MainActor
struct NoteStoreTests {
    @Test("Daily notes are deduplicated by day within a workspace")
    func deduplicatesDailyNotes() throws {
        let store = makeStore()
        let workspaceID = UUID()
        store.bindToWorkspace(workspaceID)
        let date = try #require(NoteRecord.dayFormatter.date(from: "2026-03-08"))

        let first = store.ensureDailyNote(for: date)
        let second = store.ensureDailyNote(for: date)

        #expect(first.id == second.id)
        #expect(store.notes.count == 1)
    }

    @Test("Ad hoc notes and daily notes persist and reload")
    func persistsAndReloadsNotes() throws {
        let root = tempDirectory()
        let workspaceID = UUID()

        let store = NoteStore(storageRoot: root, saveDebounceInterval: .seconds(60))
        store.bindToWorkspace(workspaceID)
        let daily = store.ensureDailyNote(for: try #require(NoteRecord.dayFormatter.date(from: "2026-03-08")))
        let adhoc = store.createAdHocNote(title: "Ideas")
        store.updateDocument(
            id: adhoc.id,
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
        #expect(reloaded.note(with: daily.id) != nil)
        let savedAdhoc = try #require(reloaded.note(with: adhoc.id))
        #expect(savedAdhoc.excerpt.contains("Track launch notes"))
    }

    @Test("Workspace binding isolates note collections")
    func isolatesWorkspaces() {
        let store = makeStore()
        let workspaceA = UUID()
        let workspaceB = UUID()

        store.bindToWorkspace(workspaceA)
        let noteA = store.createAdHocNote(title: "A")
        store.flushPendingSaves()

        store.bindToWorkspace(workspaceB)
        _ = store.createAdHocNote(title: "B")
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
        let note = store.createAdHocNote(title: "Research")

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

    @Test("Ordered notes keep today's daily note first")
    func ordersNotesWithTodayFirst() {
        let store = makeStore()
        let workspaceID = UUID()
        store.bindToWorkspace(workspaceID)

        let oldDailyDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        _ = store.ensureDailyNote(for: oldDailyDate)
        let adhoc = store.createAdHocNote(title: "Newest")
        store.updateDocument(
            id: adhoc.id,
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
        let today = store.ensureDailyNote(for: Date())

        let ordered = store.orderedNotes
        #expect(ordered.first?.id == today.id)
        #expect(ordered.contains { $0.id == adhoc.id })
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
