import Foundation
import Testing
@testable import WheelBrowser

@Suite("WidgetRuntimeBridge")
struct WidgetRuntimeBridgeTests {
    @MainActor
    @Test("Parses widget action messages")
    func parsesWidgetAction() {
        let bridge = WidgetRuntimeBridge()
        let widgetID = UUID()
        var action: WidgetRuntimeAction?

        bridge.onWidgetAction = { action = $0 }
        bridge.handleMessage(
            named: "widgetBridge",
            body: [
                "type": "widgetAction",
                "payload": [
                    "action": "moveDown",
                    "id": widgetID.uuidString,
                ],
            ]
        )

        #expect(action == .moveDown(widgetID))
    }

    @MainActor
    @Test("Parses layout toggle actions")
    func parsesLayoutToggleAction() {
        let bridge = WidgetRuntimeBridge()
        let widgetID = UUID()
        var action: WidgetRuntimeAction?

        bridge.onWidgetAction = { action = $0 }
        bridge.handleMessage(
            named: "widgetBridge",
            body: [
                "type": "widgetAction",
                "payload": [
                    "action": "toggleLayout",
                    "id": widgetID.uuidString,
                ],
            ]
        )

        #expect(action == .toggleLayout(widgetID))
    }

    @MainActor
    @Test("Parses loaded and error messages")
    func parsesLoadedAndError() {
        let bridge = WidgetRuntimeBridge()
        let widgetID = UUID()
        var loaded: UUID?
        var error: String?

        bridge.onWidgetLoaded = { loaded = $0 }
        bridge.onWidgetError = { id, message in
            loaded = id
            error = message
        }

        bridge.handleMessage(
            named: "widgetBridge",
            body: [
                "type": "widgetLoaded",
                "payload": ["id": widgetID.uuidString],
            ]
        )

        #expect(loaded == widgetID)

        bridge.handleMessage(
            named: "widgetBridge",
            body: [
                "type": "widgetError",
                "payload": [
                    "id": widgetID.uuidString,
                    "message": "boom",
                ],
            ]
        )

        #expect(loaded == widgetID)
        #expect(error == "boom")
    }

    @MainActor
    @Test("Parses height and runtime error messages")
    func parsesHeightAndRuntimeError() {
        let bridge = WidgetRuntimeBridge()
        var height: CGFloat?
        var runtimeError: String?

        bridge.onHeightChanged = { height = $0 }
        bridge.onRuntimeError = { runtimeError = $0 }

        bridge.handleMessage(
            named: "widgetBridge",
            body: [
                "type": "dashboardHeightChanged",
                "payload": ["height": 420.0],
            ]
        )
        bridge.handleMessage(
            named: "widgetBridge",
            body: [
                "type": "runtimeError",
                "payload": ["message": "bad"],
            ]
        )

        #expect(height == 420)
        #expect(runtimeError == "bad")
    }
}
