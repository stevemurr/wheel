import Foundation

/// Converts pipeline data into a `RenderInput.statCard` for display.
struct RenderStatCardSkill: WidgetSkill {
    let name = SkillName.renderStatCard

    let paramSchema = """
    {
      "label": "string (required) — KPI label",
      "value_field": "string (required) — field containing the value",
      "format": "string (optional, default 'plain') — one of: plain, currency, percent, number, temperature",
      "delta_field": "string (optional) — field containing delta value",
      "delta_label": "string (optional) — label for delta (e.g. 'vs yesterday')",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        // Handle both [[String: Any]] (standard) and [String: Any] (single object) inputs,
        // as well as [Any] containing scalar values from json_path extraction.
        let input: [[String: Any]]
        if let arrayOfDicts = params["input"] as? [[String: Any]] {
            input = arrayOfDicts
        } else if let singleDict = params["input"] as? [String: Any] {
            input = [singleDict]
        } else if let arrayOfAny = params["input"] as? [Any], let firstScalar = arrayOfAny.first {
            // Wrap scalar values in a dict with "value" key so value_field="value" works
            input = [["value": firstScalar]]
        } else {
            input = []
        }
        let label = (params["label"] as? String) ?? "Value"
        let valueField = (params["value_field"] as? String) ?? "value"
        let formatRaw = (params["format"] as? String) ?? "plain"
        let format = ValueFormat(rawValue: formatRaw) ?? .plain
        let deltaField = params["delta_field"] as? String
        let deltaLabel = params["delta_label"] as? String

        let firstRow = input.first ?? [:]
        let rawValue = firstRow[valueField]
        let valueStr = formatValue(rawValue, format: format)

        var delta: Delta?
        if let deltaField, let deltaRaw = firstRow[deltaField] {
            let deltaValue: Double
            if let d = deltaRaw as? Double { deltaValue = d }
            else if let i = deltaRaw as? Int { deltaValue = Double(i) }
            else { deltaValue = 0 }
            delta = Delta(value: deltaValue, label: deltaLabel)
        }

        return RenderInput.statCard(label: label, value: valueStr, format: format, delta: delta)
    }

    private func formatValue(_ value: Any?, format: ValueFormat) -> String {
        guard let value else { return "—" }

        switch format {
        case .currency:
            if let d = value as? Double { return String(format: "$%.2f", d) }
            if let i = value as? Int { return "$\(i)" }
        case .percent:
            if let d = value as? Double { return String(format: "%.1f%%", d) }
            if let i = value as? Int { return "\(i)%" }
        case .number:
            if let d = value as? Double { return formatNumber(d) }
            if let i = value as? Int { return formatNumber(Double(i)) }
        case .temperature:
            if let d = value as? Double { return String(format: "%.0f°", d) }
            if let i = value as? Int { return "\(i)°" }
        case .plain:
            break
        }

        if let s = value as? String { return s }
        return "\(value)"
    }

    private func formatNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}
