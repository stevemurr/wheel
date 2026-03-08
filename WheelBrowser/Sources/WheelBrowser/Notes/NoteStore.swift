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
        let todayIdentifier = Self.dayIdentifier(for: Date())
        return notes.sorted { lhs, rhs in
            if lhs.kind == .daily, lhs.dayIdentifier == todayIdentifier {
                return !(rhs.kind == .daily && rhs.dayIdentifier == todayIdentifier)
            }
            if rhs.kind == .daily, rhs.dayIdentifier == todayIdentifier {
                return false
            }
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
    func ensureDailyNote(for date: Date = Date()) -> NoteRecord {
        preconditionWorkspace()

        let identifier = Self.dayIdentifier(for: date)
        if let existing = notes.first(where: { $0.kind == .daily && $0.dayIdentifier == identifier }) {
            return existing
        }

        let note = NoteRecord(
            workspaceID: currentWorkspaceID!,
            kind: .daily,
            title: NoteRecord.displayDateFormatter.string(from: date),
            dayIdentifier: identifier
        )
        insert(note)
        persistNoteImmediately(note)
        return note
    }

    @discardableResult
    func createAdHocNote(title: String = "Untitled Note") -> NoteRecord {
        preconditionWorkspace()

        let note = NoteRecord(
            workspaceID: currentWorkspaceID!,
            kind: .adhoc,
            title: title
        )
        insert(note)
        persistNoteImmediately(note)
        return note
    }

    func renameAdHocNote(id: UUID, title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].kind == .adhoc else {
            return
        }

        notes[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].updatedAt = Date()
        markDirty(notes[index].id)
    }

    func updateDocument(id: UUID, document: NoteDocument) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        notes[index].document = document
        notes[index].excerpt = document.plainText()
        notes[index].updatedAt = Date()
        markDirty(notes[index].id)
    }

    func insertPageSource(id: UUID, source: NotePageSource) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        let document = notes[index].document.insertingPageSource(source)
        notes[index].document = document
        notes[index].excerpt = document.plainText()
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
            notes.append(note)
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

    private func workspaceDirectory(for workspaceID: UUID) -> URL {
        storageRoot.appendingPathComponent(workspaceID.uuidString, isDirectory: true)
    }

    private func preconditionWorkspace() {
        precondition(currentWorkspaceID != nil, "NoteStore must bind to a workspace before note operations")
    }

    static func dayIdentifier(for date: Date) -> String {
        NoteRecord.dayFormatter.string(from: date)
    }
}
