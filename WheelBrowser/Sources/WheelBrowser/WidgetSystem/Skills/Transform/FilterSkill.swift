import Foundation

/// Filters an array of objects using comparison operators.
struct FilterSkill: WidgetSkill {
    let name = SkillName.filter
    let sandbox: TransformSandbox

    let paramSchema = """
    {
      "field": "string (required) — field to compare",
      "operator": "string (required) — one of: eq, neq, gt, gte, lt, lte, contains, not_contains",
      "value": "any (required) — value to compare against. Must match the type of the field: use a number (not a string) for numeric fields (gt/gte/lt/lte require numbers), use a string for string fields (contains/not_contains require strings).",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = params["input"] ?? []
        return try await sandbox.execute(skill: .filter, params: params, input: input)
    }
}
