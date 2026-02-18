import Foundation

/// Errors that can occur during agent operations
enum AgentError: LocalizedError {
    // MARK: - Bridge Errors
    case webViewUnavailable
    case snapshotFailed(String)
    case clickFailed(String)
    case typeFailed(String)
    case scrollFailed(String)
    case navigationFailed(String)
    case javascriptError(String)

    // MARK: - Engine Errors
    case llmNotConfigured
    case llmRequestFailed(String)
    case invalidLLMResponse(String)
    case taskCancelled
    case maxIterationsReached
    case parseError(String)

    // MARK: - MCP Errors
    case serverStartFailed(String)
    case invalidRequest(String)
    case methodNotFound(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        // Bridge errors
        case .webViewUnavailable:
            return "WebView is not available"
        case .snapshotFailed(let reason):
            return "Failed to capture page snapshot: \(reason)"
        case .clickFailed(let reason):
            return "Failed to click element: \(reason)"
        case .typeFailed(let reason):
            return "Failed to type text: \(reason)"
        case .scrollFailed(let reason):
            return "Failed to scroll: \(reason)"
        case .navigationFailed(let reason):
            return "Failed to navigate: \(reason)"
        case .javascriptError(let message):
            return "JavaScript error: \(message)"

        // Engine errors
        case .llmNotConfigured:
            return "LLM endpoint is not configured"
        case .llmRequestFailed(let reason):
            return "LLM request failed: \(reason)"
        case .invalidLLMResponse(let reason):
            return "Invalid LLM response: \(reason)"
        case .taskCancelled:
            return "Task was cancelled"
        case .maxIterationsReached:
            return "Maximum iterations reached without completing task"
        case .parseError(let reason):
            return "Failed to parse: \(reason)"

        // MCP errors
        case .serverStartFailed(let reason):
            return "Failed to start MCP server: \(reason)"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .methodNotFound(let method):
            return "Method not found: \(method)"
        case .internalError(let reason):
            return "Internal error: \(reason)"
        }
    }
}
