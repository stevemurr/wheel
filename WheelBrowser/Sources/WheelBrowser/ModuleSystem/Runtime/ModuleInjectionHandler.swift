import Foundation
import WebKit

/// Handles injecting module content scripts, CSS, and content rules into WKWebViews.
/// Called from the page lifecycle (didFinish) and from the WebViewRepresentable coordinator.
@MainActor
final class ModuleInjectionHandler {
    static let shared = ModuleInjectionHandler()

    private(set) var moduleStore: ModuleStore?
    private(set) var moduleRuntime: ModuleRuntime?

    private init() {}

    /// Initialize with a module store. Call once at app startup.
    func configure(store: ModuleStore) {
        self.moduleStore = store
        self.moduleRuntime = ModuleRuntime(store: store)

        // Refresh LLM tool cache
        ModuleToolBridge.shared.refreshToolsCache()

        // Keep tools cache in sync when modules change
        for name: Notification.Name in [.moduleInstalled, .moduleUpdated, .moduleRemoved, .moduleEnabled, .moduleDisabled] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in
                    ModuleToolBridge.shared.refreshToolsCache()
                }
            }
        }
    }

    // MARK: - Page Load Injection

    /// Inject all matching module scripts and CSS into a webView for a given URL.
    /// Called after page load finishes.
    func injectModules(into webView: WKWebView, for url: URL) {
        guard let runtime = moduleRuntime else { return }

        // Inject CSS
        let cssScripts = runtime.cssInjectionScripts(for: url)
        for script in cssScripts {
            webView.evaluateJavaScript(script.source) { _, error in
                if let error {
                    Log.Widgets.error("CSS injection failed: \(error.localizedDescription)")
                }
            }
        }

        // Inject content scripts
        let contentScripts = runtime.contentScripts(for: url)
        for script in contentScripts {
            webView.evaluateJavaScript(script.source) { _, error in
                if let error {
                    Log.Widgets.error("Content script injection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Apply content rules (ad blockers) to a webView's configuration.
    /// Should be called when creating the webView or when blocker modules change.
    func applyContentRules(to webView: WKWebView) async {
        await moduleRuntime?.applyContentRules(to: webView)
    }

    /// Register module message handlers on a webView's content controller.
    func registerMessageHandlers(on contentController: WKUserContentController, coordinator: WKScriptMessageHandler) {
        contentController.add(coordinator, name: "wheelModuleError")
        contentController.add(coordinator, name: "wheelModuleMessage")
        contentController.add(coordinator, name: "wheelModuleResult")
    }

    /// Unregister module message handlers.
    func unregisterMessageHandlers(from contentController: WKUserContentController) {
        contentController.removeScriptMessageHandler(forName: "wheelModuleError")
        contentController.removeScriptMessageHandler(forName: "wheelModuleMessage")
        contentController.removeScriptMessageHandler(forName: "wheelModuleResult")
    }

    /// Handle incoming script messages from module content scripts.
    func handleScriptMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        switch message.name {
        case "wheelModuleError":
            let moduleId = body["moduleId"] as? String ?? "unknown"
            let error = body["error"] as? String ?? "unknown error"
            Log.Widgets.error("Module \(moduleId) error: \(error)")

        case "wheelModuleMessage":
            let moduleId = body["moduleId"] as? String ?? "unknown"
            let type = body["type"] as? String ?? ""
            let data = body["data"]
            Log.Widgets.info("Module \(moduleId) message: \(type)")
            // Forward to background context if needed
            if let id = UUID(uuidString: moduleId),
               let runtime = moduleRuntime {
                // TODO: Forward message to background context
                _ = (id, runtime, data)
            }

        case "wheelModuleResult":
            if let data = body["data"] {
                // Store the result for the caller (skill invocation)
                NotificationCenter.default.post(
                    name: .moduleResultReceived,
                    object: nil,
                    userInfo: ["data": data]
                )
            }

        default:
            break
        }
    }
}

extension Notification.Name {
    static let moduleResultReceived = Notification.Name("moduleResultReceived")
}
