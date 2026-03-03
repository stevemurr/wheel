import Foundation

/// Converts pipeline data into a `RenderInput.table` for display.
struct RenderTableSkill: WidgetSkill {
    let name = SkillName.renderTable

    let paramSchema = """
    {
      "columns": "array of objects (required) — each object has: {\"key\": \"field_name\", \"label\": \"Display Name\", \"sortable\": true/false (optional, default true), \"format\": \"plain|currency|percent|number|temperature\" (optional, default \"plain\")}. Example: [{\"key\": \"name\", \"label\": \"Name\"}, {\"key\": \"price\", \"label\": \"Price\", \"format\": \"currency\"}]",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = (params["input"] as? [[String: Any]]) ?? []

        guard let columnsRaw = params["columns"] as? [[String: Any]] else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.missing("columns"))
        }

        let columns = columnsRaw.map { col -> TableColumn in
            let key = col["key"] as? String ?? ""
            let label = col["label"] as? String ?? key
            let sortable = col["sortable"] as? Bool ?? true
            let formatRaw = col["format"] as? String ?? "plain"
            let format = ValueFormat(rawValue: formatRaw) ?? .plain
            return TableColumn(key: key, label: label, sortable: sortable, format: format)
        }

        return RenderInput.table(columns: columns, rows: input)
    }
}
