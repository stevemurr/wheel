import Foundation

@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [NoteRecord] = []
    private(set) var currentWorkspaceID: UUID?

    @ObservationIgnored private let storageRoot: URL
    @ObservationIgnored private let backend: FileSystemStoreBackend
    @ObservationIgnored private let saveScheduler: StoreSaveScheduler
    @ObservationIgnored private var dirtyNoteIDs: Set<UUID> = []

    init(
        storageRoot: URL = FileManager.appSupportDirectory.appendingPathComponent("Notes", isDirectory: true),
        saveDebounceInterval: Duration = .milliseconds(700)
    ) {
        self.storageRoot = storageRoot
        self.backend = FileSystemStoreBackend(rootURL: storageRoot)
        self.saveScheduler = StoreSaveScheduler(delay: saveDebounceInterval)
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
    }

    var orderedNotes: [NoteRecord] {
        return notes.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func bindToWorkspace(_ workspaceID: UUID) {
        if currentWorkspaceID != workspaceID {
            flushPendingSaves()
        }

        currentWorkspaceID = workspaceID
        loadNotes(for: workspaceID)
    }

    func note(with id: UUID) -> NoteRecord? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func createNote(title: String = "") -> NoteRecord {
        preconditionWorkspace()

        let document = NoteDocument.titled(title)
        let note = NoteRecord(
            workspaceID: currentWorkspaceID!,
            kind: .adhoc,
            title: document.titleLine(maxLength: Int.max),
            excerpt: document.previewText(),
            document: document
        )
        insert(note)
        persistNoteImmediately(note)
        return note
    }

    func updateDocument(id: UUID, document: NoteDocument) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].document.canonicalJSONString == document.canonicalJSONString {
            return
        }

        notes[index].document = document
        notes[index].title = document.titleLine(maxLength: Int.max)
        notes[index].excerpt = document.previewText()
        notes[index].updatedAt = Date()
        markDirty(notes[index].id)
    }

    @discardableResult
    func duplicateNote(id: UUID) -> NoteRecord? {
        guard let source = note(with: id) else { return nil }

        let duplicated = NoteRecord(
            workspaceID: source.workspaceID,
            kind: .adhoc,
            title: source.title,
            createdAt: Date(),
            updatedAt: Date(),
            excerpt: source.excerpt,
            document: source.document
        )
        insert(duplicated)
        persistNoteImmediately(duplicated)
        return duplicated
    }

    func deleteNote(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        let note = notes.remove(at: index)
        dirtyNoteIDs.remove(note.id)
        deletePersistedNote(note)
    }

    func insertPageSource(id: UUID, source: NotePageSource) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        let document = notes[index].document.insertingPageSource(source)
        notes[index].document = document
        notes[index].title = document.titleLine(maxLength: Int.max)
        notes[index].excerpt = document.previewText()
        notes[index].updatedAt = Date()
        markDirty(notes[index].id)
    }

    func flushPendingSaves() {
        saveScheduler.flush { [weak self] in
            self?.persistDirtyNotes()
        }
    }

    private func insert(_ note: NoteRecord) {
        notes.append(note)
    }

    private func markDirty(_ noteID: UUID) {
        dirtyNoteIDs.insert(noteID)
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        saveScheduler.schedule { [weak self] in
            self?.persistDirtyNotes()
        }
    }

    private func persistDirtyNotes() {
        guard !dirtyNoteIDs.isEmpty else { return }
        let dirtyIDs = dirtyNoteIDs
        dirtyNoteIDs.removeAll()

        for id in dirtyIDs {
            guard let note = note(with: id) else { continue }
            persistNoteImmediately(note)
        }
    }

    private func loadNotes(for workspaceID: UUID) {
        notes.removeAll()
        dirtyNoteIDs.removeAll()

        let store = noteStore(for: workspaceID)
        for key in (try? store.keys()) ?? [] {
            guard let note = try? store.load(key: key) else {
                continue
            }
            notes.append(normalizedRecord(note))
        }
    }

    private func persistNoteImmediately(_ note: NoteRecord) {
        do {
            try noteStore(for: note.workspaceID).save(note, for: noteKey(for: note.id))
        } catch {
            Log.Workspace.error("Failed to save note", error: error)
        }
    }

    private func deletePersistedNote(_ note: NoteRecord) {
        do {
            try noteStore(for: note.workspaceID).delete(key: noteKey(for: note.id))
        } catch {
            Log.Workspace.error("Failed to delete note", error: error)
        }
    }

    private func noteStore(for workspaceID: UUID) -> JSONBackedDirectoryStore<NoteRecord> {
        JSONBackedDirectoryStore(
            backend: backend,
            namespace: StoreNamespace(workspaceID.uuidString),
            codingConfiguration: .prettyPrintedSortedKeysISO8601
        )
    }

    private func noteKey(for id: UUID) -> StoreKey {
        StoreKey("\(id.uuidString).json")
    }

    private func preconditionWorkspace() {
        precondition(currentWorkspaceID != nil, "NoteStore must bind to a workspace before note operations")
    }

    private func normalizedRecord(_ note: NoteRecord) -> NoteRecord {
        var normalized = note
        let migratedDocument = note.document.migratedForInlineTitle(note.title)
        normalized.document = migratedDocument
        normalized.title = migratedDocument.titleLine(maxLength: Int.max)
        normalized.excerpt = migratedDocument.previewText()
        return normalized
    }
}
