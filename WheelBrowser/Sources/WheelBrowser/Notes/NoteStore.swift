import Foundation

@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [NoteRecord] = []
    private(set) var currentWorkspaceID: UUID?

    @ObservationIgnored private let storageRoot: URL
    @ObservationIgnored private let saveDebounceInterval: Duration
    @ObservationIgnored private var dirtyNoteIDs: Set<UUID> = []
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?

    init(
        storageRoot: URL = FileManager.appSupportDirectory.appendingPathComponent("Notes", isDirectory: true),
        saveDebounceInterval: Duration = .milliseconds(700)
    ) {
        self.storageRoot = storageRoot
        self.saveDebounceInterval = saveDebounceInterval
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
    }

    deinit {
        pendingSaveTask?.cancel()
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
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        persistDirtyNotes()
    }

    private func insert(_ note: NoteRecord) {
        notes.append(note)
    }

    private func markDirty(_ noteID: UUID) {
        dirtyNoteIDs.insert(noteID)
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        pendingSaveTask?.cancel()
        let delay = saveDebounceInterval
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
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

        let directory = workspaceDirectory(for: workspaceID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let note = try? decoder.decode(NoteRecord.self, from: data) else {
                continue
            }
            notes.append(normalizedRecord(note))
        }
    }

    private func persistNoteImmediately(_ note: NoteRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(note)
            let directory = workspaceDirectory(for: note.workspaceID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(note.id.uuidString).json"), options: .atomic)
        } catch {
            Log.Workspace.error("Failed to save note", error: error)
        }
    }

    private func deletePersistedNote(_ note: NoteRecord) {
        let fileURL = workspaceDirectory(for: note.workspaceID)
            .appendingPathComponent("\(note.id.uuidString).json")

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Log.Workspace.error("Failed to delete note", error: error)
        }
    }

    private func workspaceDirectory(for workspaceID: UUID) -> URL {
        storageRoot.appendingPathComponent(workspaceID.uuidString, isDirectory: true)
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
