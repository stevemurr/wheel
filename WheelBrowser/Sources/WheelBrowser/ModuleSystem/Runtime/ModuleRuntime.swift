import Foundation
import WebKit

/// Orchestrates module execution across the three runtime contexts:
/// WKContentRuleList, WKUserScript (content scripts), and JSContext (background scripts).
@MainActor
final class ModuleRuntime {
    private let store: ModuleStore
    private var compiledRuleLists: [UUID: WKContentRuleList] = [:]
    private var backgroundContexts: [UUID: WheelJSContext] = [:]

    init(store: ModuleStore) {
        self.store = store
        observeModuleChanges()
    }

    // MARK: - Content Rules (WKContentRuleList)

    /// Compile and apply content rules for all enabled blocker modules to a WKWebView configuration.
    func applyContentRules(to webView: WKWebView) async {
        let blockers = store.enabledModules(ofType: .blocker)
        for blocker in blockers {
            await applyContentRules(for: blocker, to: webView)
        }
    }

    /// Compile content rules for a single module.
    func compileContentRules(for module: ModuleInstance) async throws -> WKContentRuleList? {
        guard let rules = module.manifest.contentRules, !rules.isEmpty else { return nil }

        let jsonData = try JSONSerialization.data(withJSONObject: rules)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ModuleRuntimeError.invalidContentRules("Could not serialize rules to JSON string")
        }

        return try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "module-\(module.id.uuidString)",
            encodedContentRuleList: jsonString
        )
    }

    private func applyContentRules(for module: ModuleInstance, to webView: WKWebView) async {
        do {
            if let ruleList = try await compileContentRules(for: module) {
                compiledRuleLists[module.id] = ruleList
                webView.configuration.userContentController.add(ruleList)
            }
        } catch {
            Log.Widgets.error("Failed to compile content rules for '\(module.manifest.name)'", error: error)
        }
    }

    /// Remove content rules for a module from a WKWebView.
    func removeContentRules(for moduleId: UUID, from webView: WKWebView) {
        if let ruleList = compiledRuleLists.removeValue(forKey: moduleId) {
            webView.configuration.userContentController.remove(ruleList)
        }
    }

    // MARK: - Content Scripts (WKUserScript)

    /// Generate WKUserScripts for all modules matching a URL.
    func contentScripts(for url: URL) -> [WKUserScript] {
        let matching = store.modulesMatching(url: url)
        return matching.compactMap { module -> WKUserScript? in
            WheelContentScript.build(for: module.manifest)
        }
    }

    /// Generate CSS injection scripts for matching modules.
    func cssInjectionScripts(for url: URL) -> [WKUserScript] {
        let matching = store.modulesMatching(url: url)
        return matching.compactMap { module -> WKUserScript? in
            guard let styles = module.manifest.styles, !styles.isEmpty else { return nil }
            return WheelContentScript.buildCSSInjection(moduleId: module.id, styles: styles)
        }
    }

    // MARK: - Background Scripts (JSContext)

    /// Execute a module's background script and return the result.
    func executeBackground(moduleId: UUID, params: [String: Any]? = nil) async throws -> Any? {
        guard let module = store.module(withId: moduleId) else {
            throw ModuleRuntimeError.moduleNotFound(moduleId)
        }
        guard let script = module.manifest.backgroundScript else {
            throw ModuleRuntimeError.noBackgroundScript(module.manifest.name)
        }

        let context = getOrCreateBackgroundContext(for: module)
        return try await context.execute(script: script, params: params)
    }

    /// Execute a module's content script in a web view and return the result.
    func executeContentScript(moduleId: UUID, in webView: WKWebView) async throws -> Any? {
        guard let module = store.module(withId: moduleId) else {
            throw ModuleRuntimeError.moduleNotFound(moduleId)
        }
        guard let script = module.manifest.contentScript else {
            throw ModuleRuntimeError.noContentScript(module.manifest.name)
        }

        let wrappedScript = WheelContentScript.wrapForExecution(
            script: script,
            manifest: module.manifest
        )

        return try await webView.evaluateJavaScript(wrappedScript)
    }

    // MARK: - Lifecycle

    /// Reload a module after it has been updated.
    func reloadModule(_ moduleId: UUID) async {
        // Clear cached resources
        compiledRuleLists.removeValue(forKey: moduleId)
        backgroundContexts.removeValue(forKey: moduleId)

        // Re-compile content rules if needed
        guard let module = store.module(withId: moduleId) else { return }
        if module.manifest.contentRules != nil {
            _ = try? await compileContentRules(for: module)
        }
    }

    /// Clean up all resources for a removed module.
    func cleanupModule(_ moduleId: UUID) {
        compiledRuleLists.removeValue(forKey: moduleId)
        backgroundContexts.removeValue(forKey: moduleId)
    }

    // MARK: - Private

    private func getOrCreateBackgroundContext(for module: ModuleInstance) -> WheelJSContext {
        if let existing = backgroundContexts[module.id] {
            return existing
        }
        let context = WheelJSContext(
            moduleId: module.id,
            permissions: module.manifest.permissions
        )
        backgroundContexts[module.id] = context
        return context
    }

    private func observeModuleChanges() {
        NotificationCenter.default.addObserver(
            forName: .moduleUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let moduleId = notification.userInfo?["moduleId"] as? UUID else { return }
            Task { @MainActor [weak self] in
                await self?.reloadModule(moduleId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .moduleRemoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let moduleId = notification.userInfo?["moduleId"] as? UUID else { return }
            Task { @MainActor [weak self] in
                self?.cleanupModule(moduleId)
            }
        }
    }
}

// MARK: - Errors

enum ModuleRuntimeError: LocalizedError {
    case moduleNotFound(UUID)
    case noBackgroundScript(String)
    case noContentScript(String)
    case invalidContentRules(String)
    case executionFailed(String)
    case timeout
    case sandboxViolation(String)

    var errorDescription: String? {
        switch self {
        case .moduleNotFound(let id):
            return "Module not found: \(id)"
        case .noBackgroundScript(let name):
            return "Module '\(name)' has no background script"
        case .noContentScript(let name):
            return "Module '\(name)' has no content script"
        case .invalidContentRules(let detail):
            return "Invalid content rules: \(detail)"
        case .executionFailed(let detail):
            return "Module execution failed: \(detail)"
        case .timeout:
            return "Module execution timed out (5s limit)"
        case .sandboxViolation(let detail):
            return "Sandbox violation: \(detail)"
        }
    }
}
