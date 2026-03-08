import SwiftUI

struct NoteWindowContainer: View {
    var noteStore: NoteStore
    var noteWindowState: NoteWindowState
    let containerSize: CGSize

    var body: some View {
        Group {
            if let window = noteWindowState.window,
               let note = noteStore.note(with: window.noteID) {
                NoteWindow(
                    item: window,
                    note: note,
                    noteStore: noteStore,
                    noteWindowState: noteWindowState
                )
                .modifier(FloatingWindowPositionModifier(item: window, containerSize: containerSize))
                .zIndex(1000)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    )
                )
            }
        }
        .onAppear {
            noteWindowState.containerSize = containerSize
        }
        .onChange(of: containerSize) { _, newSize in
            noteWindowState.containerSize = newSize
        }
    }
}

private struct NoteWindow: View {
    var item: NoteWindowItem
    var note: NoteRecord
    var noteStore: NoteStore
    var noteWindowState: NoteWindowState

    @State private var editorBridge = NoteEditorBridge()
    @State private var draftTitle = ""

    var body: some View {
        FloatingWindowShell(
            item: item,
            containerSize: noteWindowState.containerSize,
            onClose: {
                noteStore.flushPendingSaves()
                noteWindowState.close()
            },
            onBringToFront: noteWindowState.bringToFront,
            onMinimize: noteWindowState.minimize,
            onToggleMaximize: noteWindowState.toggleMaximize,
            onUpdatePosition: noteWindowState.updatePosition,
            onUpdateSize: noteWindowState.updateSize
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 0) {
                header
                Divider()
                NoteEditorView(bridge: editorBridge)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onAppear(perform: configureBridge)
        .onAppear {
            syncWindow(with: note)
        }
        .onChange(of: item.noteID) { _, _ in
            syncWindow(with: note)
        }
        .onChange(of: note.updatedAt) { _, _ in
            syncWindow(with: note)
        }
        .onChange(of: note.displayTitle) { _, newValue in
            noteWindowState.updateTitle(newValue)
            if note.kind == .adhoc {
                draftTitle = note.title
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if note.kind == .daily {
                        Text(note.displayTitle)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    } else {
                        TextField("Untitled Note", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .onChange(of: draftTitle) { _, newValue in
                                noteStore.renameAdHocNote(id: note.id, title: newValue)
                                noteWindowState.updateTitle(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : newValue)
                            }
                    }

                    HStack(spacing: 8) {
                        noteTypeBadge
                        Text("Updated \(note.shortUpdatedText)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !note.excerpt.isEmpty {
                Text(note.excerpt)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var noteTypeBadge: some View {
        Text(note.kind == .daily ? "Daily Note" : "Note")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(note.kind == .daily ? Color.accentColor : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill((note.kind == .daily ? Color.accentColor : Color.orange).opacity(0.12))
            )
    }

    private func configureBridge() {
        editorBridge.onReady = {
            guard let currentNote = noteStore.note(with: item.noteID) else { return }
            editorBridge.activate(noteID: currentNote.id)
            editorBridge.loadDocumentIfNeeded(currentNote.document, force: true)
            editorBridge.focusEditor()
        }
        editorBridge.onDocumentChanged = { document in
            noteStore.updateDocument(id: item.noteID, document: document)
        }
        editorBridge.onEditorError = { message in
            Log.Overlay.error("Note editor error: \(message)")
        }
    }

    private func syncWindow(with note: NoteRecord) {
        editorBridge.activate(noteID: note.id)
        editorBridge.loadDocumentIfNeeded(note.document, force: false)
        noteWindowState.updateTitle(note.displayTitle)
        if note.kind == .adhoc, draftTitle != note.title {
            draftTitle = note.title
        }
    }
}
