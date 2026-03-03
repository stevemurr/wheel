import Foundation

/// Sorts an array of objects by a field.
struct SortSkill: WidgetSkill {
    let name = SkillName.sort
    let sandbox: TransformSandbox

    let paramSchema = """
    {
      "field": "string (required) — field to sort by",
      "order": "string (optional, default 'desc') — 'asc' or 'desc'",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = params["input"] ?? []
        return try await sandbox.execute(skill: .sort, params: params, input: input)
    }
}
