import Foundation
import WebKit

/// Handles WKScriptMessage dispatching for messages from injected JavaScript.
///
/// Currently handles:
/// - `overlayWindow` messages (Cmd+Click overlay opening)
/// - `linkHover` messages (reserved for link preview)
enum ScriptMessageHandler {

    /// Process an incoming script message and dispatch to the appropriate handler.
    static func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            Log.LinkPreview.warning("Invalid message format")
            return
        }

        switch message.name {
        case "overlayWindow":
            handleOverlayWindow(type: type, body: body)
        case "wheelModuleError", "wheelModuleMessage", "wheelModuleResult":
            Task { @MainActor in
                ModuleInjectionHandler.shared.handleScriptMessage(message)
            }
        default:
            break
        }
    }

    // MARK: - Overlay Window

    private static func handleOverlayWindow(type: String, body: [String: Any]) {
        guard type == "openOverlay" else { return }

        Task { @MainActor in
            guard let urlString = body["url"] as? String,
                  let url = URL(string: urlString),
                  let x = body["x"] as? Double,
                  let y = body["y"] as? Double else {
                Log.Overlay.warning("Invalid overlay data")
                return
            }

            let linkText = body["text"] as? String
            let position = CGPoint(x: x, y: y)

            Log.Overlay.info("Opening overlay: \(urlString)")
            OverlayWindowManager.shared.openOverlay(url: url, title: linkText, at: position)
        }
    }
}
