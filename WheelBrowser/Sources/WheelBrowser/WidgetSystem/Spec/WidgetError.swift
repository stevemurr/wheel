import Foundation

/// Errors that can occur in the widget pipeline system.
enum WidgetError: LocalizedError {
    /// The skill name is not recognized
    case unknownSkill(String)

    /// A `{{step_id.output}}` reference points to a nonexistent step
    case invalidReference(stepId: String, ref: String)

    /// The spec failed validation
    case validationFailed(SpecValidationError)

    /// A pipeline step failed during execution
    case executionFailed(stepId: String, underlying: Error)

    /// Rendering failed
    case renderFailed(String)

    /// The LLM failed to generate a valid spec
    case specGenerationFailed(String)

    /// A pipeline step timed out
    case stepTimeout(stepId: String)

    var errorDescription: String? {
        switch self {
        case .unknownSkill(let name):
            return "Unknown skill: \(name)"
        case .invalidReference(let stepId, let ref):
            return "Step '\(stepId)' references unknown step: \(ref)"
        case .validationFailed(let error):
            return "Validation failed at pass \(error.pass): \(error.message)"
        case .executionFailed(let stepId, let underlying):
            return "Step '\(stepId)' failed: \(underlying.localizedDescription)"
        case .renderFailed(let detail):
            return "Render failed: \(detail)"
        case .specGenerationFailed(let detail):
            return "Spec generation failed: \(detail)"
        case .stepTimeout(let stepId):
            return "Step '\(stepId)' timed out"
        }
    }
}

/// Detailed error from spec validation, including which pass and step failed.
struct SpecValidationError: Error, LocalizedError {
    /// Which validation pass found the error (1-5)
    let pass: Int

    /// Which step index caused the error (nil for spec-level errors)
    let stepIndex: Int?

    /// Human-readable error message
    let message: String

    /// Suggestion for how to fix the error (useful for LLM repair prompts)
    let suggestion: String?

    var errorDescription: String? {
        var desc = "Validation pass \(pass)"
        if let idx = stepIndex { desc += ", step \(idx)" }
        desc += ": \(message)"
        if let suggestion { desc += " Suggestion: \(suggestion)" }
        return desc
    }
}
