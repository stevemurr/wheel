import Foundation
import WebKit

@MainActor
final class NoteEditorBridge: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onDocumentChanged: ((NoteDocument) -> Void)?
    var onEditorError: ((String) -> Void)?

    private weak var webView: WKWebView?
    private var isReady = false
    private var queuedScripts: [String] = []
    private var lastDocumentFingerprint: String?
    private var activeNoteID: UUID?

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func detach() {
        webView = nil
        isReady = false
        queuedScripts.removeAll()
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
        send(command: "loadDocument", payload: DocumentPayload(document: document.root))
    }

    func focusEditor() {
        send(command: "focusEditor", payload: EmptyPayload())
    }

    func insertSourceBlock(_ source: NotePageSource) {
        send(command: "insertSourceBlock", payload: SourcePayload(source: source))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "noteEditorBridge",
              let body = message.body as? [String: Any] else {
            return
        }
        handleMessage(body)
    }

    func handleMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "ready":
            isReady = true
            flushQueuedScripts()
            onReady?()
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

    private func send<Payload: Encodable>(command: String, payload: Payload) {
        guard let webView else { return }

        do {
            let data = try JSONEncoder().encode(payload)
            let json = String(decoding: data, as: UTF8.self)
            let escaped = JavaScriptEscaper.escape(json)
            let script = "window.NoteEditor.receiveCommand('\(command)', JSON.parse('\(escaped)'));"

            if isReady {
                webView.evaluateJavaScript(script, completionHandler: nil)
            } else {
                queuedScripts.append(script)
            }
        } catch {
            onEditorError?("Failed to encode note editor payload: \(error.localizedDescription)")
        }
    }

    private func flushQueuedScripts() {
        guard let webView else { return }
        let scripts = queuedScripts
        queuedScripts.removeAll()
        for script in scripts {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
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
