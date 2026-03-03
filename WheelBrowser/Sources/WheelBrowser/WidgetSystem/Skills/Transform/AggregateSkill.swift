import Foundation

/// Aggregates data using count/sum/avg/min/max/first/last with optional group_by.
struct AggregateSkill: WidgetSkill {
    let name = SkillName.aggregate
    let sandbox: TransformSandbox

    let paramSchema = """
    {
      "operation": "string (required) — one of: count, sum, avg, min, max, first, last",
      "field": "string (optional) — field to aggregate. Required for sum/avg/min/max/first/last.",
      "group_by": "string (optional) — field to group by before aggregating",
      "input": "reference (required) — {{step_id.output}} from a previous step",
      "_output_format": "Without group_by: [{\"value\": <result>}]. With group_by: [{\"<group_by_field>\": \"<key>\", \"value\": <result>}, ...]. Downstream steps must use 'value' as the field name to access the aggregated result."
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = params["input"] ?? []
        return try await sandbox.execute(skill: .aggregate, params: params, input: input)
    }
}
