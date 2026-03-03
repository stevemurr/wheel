import Foundation

/// Filters an array of objects using comparison operators.
struct FilterSkill: WidgetSkill {
    let name = SkillName.filter
    let sandbox: TransformSandbox

    let paramSchema = """
    {
      "field": "string (required) — field to compare",
      "operator": "string (required) — one of: eq, neq, gt, gte, lt, lte, contains, not_contains",
      "value": "any (required) — value to compare against",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = params["input"] ?? []
        return try sandbox.execute(skill: .filter, params: params, input: input)
    }
}
