import Foundation

/// Protocol for all widget pipeline skills.
/// Each skill takes parameters (possibly including resolved references) and returns output data.
protocol WidgetSkill: Sendable {
    /// The skill identifier
    var name: SkillName { get }

    /// JSON schema string describing the expected parameters
    var paramSchema: String { get }

    /// Execute the skill with the given parameters.
    /// - Parameter params: Resolved parameters dictionary
    /// - Returns: Output data (typically `[[String: Any]]` for acquisition, or `RenderInput` for render)
    func execute(params: [String: Any]) async throws -> Any
}
