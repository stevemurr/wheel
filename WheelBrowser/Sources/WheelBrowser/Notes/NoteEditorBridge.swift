import Foundation

@MainActor
final class NoteEditorBridge: QueuedScriptBridge {
    var onReady: (() -> Void)?
    var onDocumentChanged: ((NoteDocument) -> Void)?
    var onEditorError: ((String) -> Void)?

    private var lastDocumentFingerprint: String?
    private var activeNoteID: UUID?

    init() {
        super.init(messageHandlerName: "noteEditorBridge", javaScriptReceiver: "NoteEditor")
    }

    override func detach() {
        super.detach()
        lastDocumentFingerprint = nil
        activeNoteID = nil
    }

    func activate(noteID: UUID) {
        if activeNoteID != noteID {
            activeNoteID = noteID
            lastDocumentFingerprint = nil
        }
    }

    func loadDocumentIfNeeded(_ document: NoteDocument, force: Bool = false) {
        guard let fingerprint = fingerprint(for: document),
              force || fingerprint != lastDocumentFingerprint else {
            return
        }

        lastDocumentFingerprint = fingerprint
        sendCommand("loadDocument", payload: DocumentPayload(document: document.root))
    }

    func focusEditor() {
        sendCommand("focusEditor", payload: EmptyPayload())
    }

    func insertSourceBlock(_ source: NotePageSource) {
        sendCommand("insertSourceBlock", payload: SourcePayload(source: source))
    }

    override func bridgeDidBecomeReady() {
        onReady?()
    }

    override func didReceiveMessage(type: String, payload: [String: Any]) {
        switch type {
        case "documentChanged":
            guard let document = decodeDocument(payload) else {
                onEditorError?("Editor sent an invalid document payload.")
                return
            }
            lastDocumentFingerprint = fingerprint(for: document)
            onDocumentChanged?(document)
        case "editorError":
            onEditorError?(payload["message"] as? String ?? "Unknown editor error")
        default:
            break
        }
    }

    override func reportBridgeError(_ message: String) {
        onEditorError?(message)
    }

    private func decodeDocument(_ payload: [String: Any]) -> NoteDocument? {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let payload = try JSONDecoder().decode(DocumentPayload.self, from: data)
            return NoteDocument(root: payload.document)
        } catch {
            return nil
        }
    }

    private func fingerprint(for document: NoteDocument) -> String? {
        document.canonicalJSONString
    }
}

private struct DocumentPayload: Codable {
    let document: [String: AnyCodable]
}

private struct SourcePayload: Codable {
    let source: NotePageSource
}

private struct EmptyPayload: Codable {}
