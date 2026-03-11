import Foundation

enum WidgetRuntimeAction: Equatable {
    case remove(UUID)
    case moveUp(UUID)
    case moveDown(UUID)
    case toggleLayout(UUID)
    case toggleVisualization(UUID)
    case refresh(UUID)
    case openLink(UUID, URL)
}

@MainActor
final class WidgetRuntimeBridge: QueuedScriptBridge {
    var onReady: (() -> Void)?
    var onWidgetLoaded: ((UUID) -> Void)?
    var onWidgetError: ((UUID, String) -> Void)?
    var onWidgetAction: ((WidgetRuntimeAction) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?
    var onRuntimeError: ((String) -> Void)?

    init() {
        super.init(messageHandlerName: "widgetBridge", javaScriptReceiver: "WidgetDashboard")
    }

    func bootstrapDashboard(records: [WidgetRecord], isEditing: Bool) {
        sendCommand(
            "bootstrapDashboard",
            payload: DashboardPayload(widgets: records.map(DashboardWidgetPayload.init), isEditing: isEditing)
        )
    }

    func setDashboardState(records: [WidgetRecord], isEditing: Bool) {
        sendCommand(
            "setDashboardState",
            payload: DashboardPayload(widgets: records.map(DashboardWidgetPayload.init), isEditing: isEditing)
        )
    }

    func refreshWidget(id: UUID) {
        sendCommand("refreshWidget", payload: RefreshPayload(id: id))
    }

    override func bridgeDidBecomeReady() {
        onReady?()
    }

    override func didReceiveMessage(type: String, payload: [String: Any]) {
        switch type {
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

    override func reportBridgeError(_ message: String) {
        onRuntimeError?(message)
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
        case "toggleLayout":
            return .toggleLayout(id)
        case "toggleVisualization":
            return .toggleVisualization(id)
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
    let widgets: [DashboardWidgetPayload]
    let isEditing: Bool
}

private struct RefreshPayload: Encodable {
    let id: UUID
}

private struct DashboardWidgetPayload: Encodable {
    let manifest: WidgetManifest
    let layoutPreference: WidgetLayoutPreference
    let visualizationPreference: WidgetVisualizationPreference

    init(record: WidgetRecord) {
        manifest = record.manifest
        layoutPreference = record.layoutPreference
        visualizationPreference = record.visualizationPreference
    }
}
