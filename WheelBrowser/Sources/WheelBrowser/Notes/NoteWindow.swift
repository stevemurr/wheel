import SwiftUI

struct NoteWindowContainer: View {
    var noteStore: NoteStore
    var noteWindowState: NoteWindowState
    let onCopyNote: (NoteRecord) -> Void
    let onDeleteNote: (NoteRecord) -> Void
    let containerSize: CGSize

    var body: some View {
        Group {
            if let window = noteWindowState.window,
               let note = noteStore.note(with: window.noteID) {
                NoteWindow(
                    item: window,
                    note: note,
                    noteStore: noteStore,
                    noteWindowState: noteWindowState,
                    onCopyNote: onCopyNote,
                    onDeleteNote: onDeleteNote
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
    let onCopyNote: (NoteRecord) -> Void
    let onDeleteNote: (NoteRecord) -> Void

    @State private var editorBridge = NoteEditorBridge()
    @State private var isShowingDeleteConfirmation = false

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
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            noteTypeBadge

            Text("Updated \(note.shortUpdatedText)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(action: { onCopyNote(note) }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(NoteWindowHeaderActionButtonStyle())
            .help("Copy note")

            Button(role: .destructive, action: { isShowingDeleteConfirmation = true }) {
                Image(systemName: "trash")
            }
            .buttonStyle(NoteWindowHeaderActionButtonStyle())
            .help("Delete note")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Delete this note?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) {
                onDeleteNote(note)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(note.displayTitle)
        }
    }

    private var noteTypeBadge: some View {
        Text("Note")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
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
    }
}

private struct NoteWindowHeaderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.65 : 0.88))
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.05))
            )
    }
}
