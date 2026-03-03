import Foundation

/// Converts pipeline data into a `RenderInput.chart` for display.
struct RenderChartSkill: WidgetSkill {
    let name = SkillName.renderChart

    let paramSchema = """
    {
      "chart_type": "string (required) — one of: line, bar, area, scatter, pie, doughnut. Use 'line' or 'area' for time series, 'bar' for comparisons, 'pie'/'doughnut' for proportions. For pie/doughnut, x_field is the label and y_field is the value.",
      "title": "string (optional) — chart title",
      "x_field": "string (required) — field for x-axis values (or label field for pie/doughnut)",
      "y_field": "string (required) — field for y-axis values",
      "series_field": "string (optional) — field to split data into multiple series (not used with pie/doughnut)",
      "color_scheme": "string (optional) — color scheme name",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = (params["input"] as? [[String: Any]]) ?? []
        let chartTypeRaw = (params["chart_type"] as? String) ?? "line"
        let chartType = ChartConfig.ChartType(rawValue: chartTypeRaw) ?? .line
        let title = params["title"] as? String
        let xField = (params["x_field"] as? String) ?? "x"
        let yField = (params["y_field"] as? String) ?? "y"
        let seriesField = params["series_field"] as? String
        let colorScheme = params["color_scheme"] as? String

        return RenderInput.chart(config: ChartConfig(
            type: chartType,
            title: title,
            data: input,
            xField: xField,
            yField: yField,
            seriesField: seriesField,
            colorScheme: colorScheme
        ))
    }
}
