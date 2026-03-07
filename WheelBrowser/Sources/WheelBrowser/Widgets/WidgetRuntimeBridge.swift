import Foundation
import WebKit

enum WidgetRuntimeAction: Equatable {
    case remove(UUID)
    case moveUp(UUID)
    case moveDown(UUID)
    case refresh(UUID)
    case openLink(UUID, URL)
}

@MainActor
final class WidgetRuntimeBridge: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onWidgetLoaded: ((UUID) -> Void)?
    var onWidgetError: ((UUID, String) -> Void)?
    var onWidgetAction: ((WidgetRuntimeAction) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?
    var onRuntimeError: ((String) -> Void)?

    private weak var webView: WKWebView?
    private var isReady = false
    private var queuedScripts: [String] = []

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func detach() {
        webView = nil
        isReady = false
        queuedScripts.removeAll()
    }

    func bootstrapDashboard(records: [WidgetRecord], isEditing: Bool) {
        send(
            command: "bootstrapDashboard",
            payload: DashboardPayload(widgets: records.map(\.manifest), isEditing: isEditing)
        )
    }

    func setDashboardState(records: [WidgetRecord], isEditing: Bool) {
        send(
            command: "setDashboardState",
            payload: DashboardPayload(widgets: records.map(\.manifest), isEditing: isEditing)
        )
    }

    func refreshWidget(id: UUID) {
        send(command: "refreshWidget", payload: RefreshPayload(id: id))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "widgetBridge",
              let body = message.body as? [String: Any] else {
            return
        }
        handleMessage(named: message.name, body: body)
    }

    func handleMessage(named name: String, body: [String: Any]) {
        guard name == "widgetBridge",
              let type = body["type"] as? String else {
            return
        }

        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "ready":
            isReady = true
            flushQueuedScripts()
            onReady?()
        case "widgetLoaded":
            if let id = uuid(from: payload["id"]) {
                onWidgetLoaded?(id)
            }
        case "widgetError":
            if let id = uuid(from: payload["id"]) {
                onWidgetError?(id, payload["message"] as? String ?? "Unknown widget error")
            }
        case "widgetAction":
            if let action = parseAction(payload) {
                onWidgetAction?(action)
            }
        case "dashboardHeightChanged":
            if let height = payload["height"] as? Double {
                onHeightChanged?(CGFloat(height))
            }
        case "runtimeError":
            onRuntimeError?(payload["message"] as? String ?? "Unknown runtime error")
        default:
            break
        }
    }

    private func send<Payload: Encodable>(command: String, payload: Payload) {
        guard let webView else { return }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            let json = String(decoding: data, as: UTF8.self)
            let escaped = JavaScriptEscaper.escape(json)
            let script = "window.WidgetDashboard.receiveCommand('\(command)', JSON.parse('\(escaped)'));"

            if isReady {
                webView.evaluateJavaScript(script, completionHandler: nil)
            } else {
                queuedScripts.append(script)
            }
        } catch {
            onRuntimeError?("Failed to encode widget runtime payload: \(error.localizedDescription)")
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

    private func parseAction(_ payload: [String: Any]) -> WidgetRuntimeAction? {
        guard let action = payload["action"] as? String,
              let id = uuid(from: payload["id"]) else {
            return nil
        }

        switch action {
        case "remove":
            return .remove(id)
        case "moveUp":
            return .moveUp(id)
        case "moveDown":
            return .moveDown(id)
        case "refresh":
            return .refresh(id)
        case "openLink":
            guard let urlString = payload["url"] as? String,
                  let url = URL(string: urlString) else {
                return nil
            }
            return .openLink(id, url)
        default:
            return nil
        }
    }

    private func uuid(from value: Any?) -> UUID? {
        if let string = value as? String {
            return UUID(uuidString: string)
        }
        return nil
    }
}

private struct DashboardPayload: Encodable {
    let widgets: [WidgetManifest]
    let isEditing: Bool
}

private struct RefreshPayload: Encodable {
    let id: UUID
}
