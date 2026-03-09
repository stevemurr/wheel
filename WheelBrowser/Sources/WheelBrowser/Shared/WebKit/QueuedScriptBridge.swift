import Foundation
import WebKit

@MainActor
class QueuedScriptBridge: NSObject, WKScriptMessageHandler {
    let messageHandlerName: String

    private let javaScriptReceiver: String
    private weak var webView: WKWebView?
    private var isReady = false
    private var queuedScripts: [String] = []

    init(messageHandlerName: String, javaScriptReceiver: String) {
        self.messageHandlerName = messageHandlerName
        self.javaScriptReceiver = javaScriptReceiver
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func detach() {
        webView = nil
        isReady = false
        queuedScripts.removeAll()
    }

    func sendCommand<Payload: Encodable>(_ command: String, payload: Payload) {
        guard let webView else { return }

        do {
            let data = try JSONEncoder().encode(payload)
            let json = String(decoding: data, as: UTF8.self)
            let escaped = JavaScriptEscaper.escape(json)
            let script = "window.\(javaScriptReceiver).receiveCommand('\(command)', JSON.parse('\(escaped)'));"

            if isReady {
                webView.evaluateJavaScript(script, completionHandler: nil)
            } else {
                queuedScripts.append(script)
            }
        } catch {
            reportBridgeError("Failed to encode \(messageHandlerName) payload: \(error.localizedDescription)")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName,
              let body = message.body as? [String: Any] else {
            return
        }
        handleMessage(named: message.name, body: body)
    }

    func handleMessage(_ body: [String: Any]) {
        handleMessage(named: messageHandlerName, body: body)
    }

    func handleMessage(named name: String, body: [String: Any]) {
        guard name == messageHandlerName,
              let type = body["type"] as? String else {
            return
        }

        let payload = body["payload"] as? [String: Any] ?? [:]
        if type == "ready" {
            isReady = true
            flushQueuedScripts()
            bridgeDidBecomeReady()
            return
        }

        didReceiveMessage(type: type, payload: payload)
    }

    func bridgeDidBecomeReady() {}

    func didReceiveMessage(type: String, payload: [String: Any]) {}

    func reportBridgeError(_ message: String) {}

    private func flushQueuedScripts() {
        guard let webView else { return }
        let scripts = queuedScripts
        queuedScripts.removeAll()
        for script in scripts {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
