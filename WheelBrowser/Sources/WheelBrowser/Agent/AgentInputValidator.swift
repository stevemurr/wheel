import Foundation

/// Validates and sanitizes agent task inputs for security
public struct AgentInputValidator {
    /// Maximum allowed task length in characters
    public static let maxTaskLength = 10_000

    /// Patterns that indicate potentially dangerous content
    private static let dangerousPatterns: [String] = [
        "<script",
        "javascript:",
        "data:text/html",
        "eval(",
        "Function(",
        "setTimeout(",
        "setInterval(",
        "document.write(",
        "innerHTML",
        "outerHTML"
    ]

    /// Validates and sanitizes a task string
    /// - Parameter task: The raw task input
    /// - Returns: The validated and trimmed task
    /// - Throws: AgentError.invalidInput if the task is invalid
    public static func validateTask(_ task: String) throws -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty input
        guard !trimmed.isEmpty else {
            throw AgentError.invalidInput("Task cannot be empty")
        }

        // Check length limit
        guard trimmed.count <= maxTaskLength else {
            throw AgentError.invalidInput("Task exceeds maximum length of \(maxTaskLength) characters")
        }

        // Check for dangerous patterns
        let lowercased = trimmed.lowercased()
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern.lowercased()) {
                throw AgentError.invalidInput("Task contains potentially dangerous content")
            }
        }

        return trimmed
    }
}
