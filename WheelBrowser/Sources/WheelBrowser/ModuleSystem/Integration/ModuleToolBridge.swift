import Foundation
import WebKit

/// Bridges module system with the LLM chat agent.
/// Modules with `trigger: "manual"` are exposed as tools the LLM can invoke.
final class ModuleToolBridge: @unchecked Sendable {
    static let shared = ModuleToolBridge()

    private init() {}

    /// Cached tools prompt section — updated when modules change.
    private var cachedToolsSection: String?

    /// Update the cached tools section. Call from MainActor when modules change.
    @MainActor
    func refreshToolsCache() {
        guard let store = ModuleInjectionHandler.shared.moduleStore else {
            cachedToolsSection = nil
            return
        }
        let manualModules = store.manualModules()
        guard !manualModules.isEmpty else {
            cachedToolsSection = nil
            return
        }
        cachedToolsSection = buildToolsSection(from: manualModules)
    }

    // MARK: - Tool Descriptions for System Prompt

    /// Generate a tools section for the system prompt listing all available module tools.
    func toolsPromptSection() -> String? {
        return cachedToolsSection
    }

    @MainActor
    private func buildToolsSection(from manualModules: [ModuleInstance]) -> String? {
        guard !manualModules.isEmpty else { return nil }

        var lines = [
            "",
            "## Available Module Tools",
            "",
            "You have access to the following tools. To use a tool, include a tool call in your response:",
            "```",
            "[TOOL_CALL: tool_name]",
            "optional parameters as JSON",
            "[/TOOL_CALL]",
            "```",
            "",
        ]

        for module in manualModules {
            lines.append("### \(module.manifest.name)")
            lines.append("- **Description**: \(module.manifest.description)")
            lines.append("- **Tool name**: `\(toolName(for: module.manifest))`")

            if module.manifest.contentScript != nil {
                lines.append("- **Context**: Runs in the current page (has DOM access)")
            }
            if module.manifest.backgroundScript != nil {
                lines.append("- **Context**: Runs in background (can fetch network data)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Build the enhanced system prompt that includes module tool definitions.
    func enhancedSystemPrompt(base: String) -> String {
        guard let toolsSection = toolsPromptSection() else { return base }
        return base + "\n" + toolsSection
    }

    // MARK: - Tool Call Parsing

    /// Check if an assistant response contains a tool call and extract it.
    func parseToolCall(from response: String) -> ToolCall? {
        guard let startRange = response.range(of: "[TOOL_CALL:"),
              let endRange = response.range(of: "[/TOOL_CALL]") else {
            return nil
        }

        let afterStart = response[startRange.upperBound..<endRange.lowerBound]
        let lines = afterStart.split(separator: "\n", maxSplits: 1)
        guard let firstLine = lines.first else { return nil }

        let name = firstLine.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "]")))
        let params: [String: Any]?

        if lines.count > 1 {
            let paramsString = String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = paramsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                params = json
            } else {
                params = nil
            }
        } else {
            params = nil
        }

        return ToolCall(name: name, params: params)
    }

    // MARK: - Tool Execution

    /// Execute a tool call by finding the matching module and running its script.
    @MainActor
    func executeToolCall(
        _ toolCall: ToolCall,
        webView: WKWebView?
    ) async throws -> String {
        guard let store = ModuleInjectionHandler.shared.moduleStore,
              let runtime = ModuleInjectionHandler.shared.moduleRuntime else {
            throw ModuleRuntimeError.executionFailed("Module system not initialized")
        }

        // Find matching module
        let manualModules = store.manualModules()
        guard let module = manualModules.first(where: {
            toolName(for: $0.manifest) == toolCall.name
        }) else {
            throw ModuleRuntimeError.executionFailed("No module found for tool '\(toolCall.name)'")
        }

        // Execute the appropriate script
        if let _ = module.manifest.contentScript, let webView {
            // Content script — runs in page context
            let result = try await runtime.executeContentScript(moduleId: module.id, in: webView)
            return formatResult(result)
        } else if module.manifest.backgroundScript != nil {
            // Background script — runs in JSContext
            let result = try await runtime.executeBackground(moduleId: module.id, params: toolCall.params)
            return formatResult(result)
        } else {
            throw ModuleRuntimeError.executionFailed("Module '\(module.manifest.name)' has no executable script")
        }
    }

    // MARK: - Helpers

    /// Generate a tool name from a module manifest (snake_case of name).
    func toolName(for manifest: ModuleManifest) -> String {
        manifest.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func formatResult(_ result: Any?) -> String {
        guard let result else { return "No result returned" }

        if let dict = result as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        if let array = result as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return "\(result)"
    }
}

// MARK: - Tool Call Model

struct ToolCall {
    let name: String
    let params: [String: Any]?
}
