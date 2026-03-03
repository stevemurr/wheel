import Foundation

/// Maps/projects fields from input objects using templates.
struct MapFieldsSkill: WidgetSkill {
    let name = SkillName.mapFields
    let sandbox: TransformSandbox

    let paramSchema = """
    {
      "mapping": "object (required) — keys are output field names, values are either input field names or templates like '{{field1}} - {{field2}}'",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = params["input"] ?? []
        return try await sandbox.execute(skill: .mapFields, params: params, input: input)
    }
}
