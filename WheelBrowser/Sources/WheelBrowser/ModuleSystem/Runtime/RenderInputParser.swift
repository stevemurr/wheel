import Foundation

/// Converts raw dictionaries from `wheel.render()` calls into typed `RenderInput` values.
enum RenderInputParser {

    /// Parse a dictionary from wheel.render(spec) into a RenderInput.
    static func parse(_ dict: [String: Any]) -> RenderInput? {
        guard let type = dict["type"] as? String else { return nil }

        switch type {
        case "stat_card":
            return parseStatCard(dict)
        case "list":
            return parseList(dict)
        case "chart":
            return parseChart(dict)
        case "table":
            return parseTable(dict)
        case "composite":
            return parseComposite(dict)
        default:
            return nil
        }
    }

    // MARK: - Stat Card

    private static func parseStatCard(_ dict: [String: Any]) -> RenderInput? {
        guard let label = dict["label"] as? String,
              let value = dict["value"] as? String else { return nil }

        let format: ValueFormat
        if let formatStr = dict["format"] as? String {
            format = ValueFormat(rawValue: formatStr) ?? .plain
        } else {
            format = .plain
        }

        var delta: Delta?
        if let deltaDict = dict["delta"] as? [String: Any],
           let deltaValue = deltaDict["value"] as? Double {
            let deltaLabel = deltaDict["label"] as? String
            delta = Delta(value: deltaValue, label: deltaLabel)
        }

        return .statCard(label: label, value: value, format: format, delta: delta)
    }

    // MARK: - List

    private static func parseList(_ dict: [String: Any]) -> RenderInput? {
        guard let title = dict["title"] as? String,
              let itemsArray = dict["items"] as? [[String: Any]] else { return nil }

        let items = itemsArray.map { item -> ListItem in
            let headline = item["headline"] as? String ?? ""
            let subheadline = item["subheadline"] as? String
            let link = item["link"] as? String

            var badge: ListItem.Badge?
            if let badgeText = item["badge"] as? String {
                let colorStr = item["badge_color"] as? String ?? "gray"
                let color = ListItem.Badge.BadgeColor(rawValue: colorStr) ?? .gray
                badge = ListItem.Badge(text: badgeText, color: color)
            }

            return ListItem(headline: headline, subheadline: subheadline, badge: badge, link: link)
        }

        return .list(title: title, items: items)
    }

    // MARK: - Chart

    private static func parseChart(_ dict: [String: Any]) -> RenderInput? {
        guard let chartTypeStr = dict["chart_type"] as? String,
              let chartType = ChartConfig.ChartType(rawValue: chartTypeStr),
              let data = dict["data"] as? [[String: Any]],
              let xField = dict["x_field"] as? String,
              let yField = dict["y_field"] as? String else { return nil }

        let config = ChartConfig(
            type: chartType,
            title: dict["title"] as? String,
            data: data,
            xField: xField,
            yField: yField,
            seriesField: dict["series_field"] as? String,
            colorScheme: dict["color_scheme"] as? String
        )

        return .chart(config: config)
    }

    // MARK: - Table

    private static func parseTable(_ dict: [String: Any]) -> RenderInput? {
        guard let columnsArray = dict["columns"] as? [[String: Any]],
              let rows = dict["rows"] as? [[String: Any]] else { return nil }

        let columns = columnsArray.map { col -> TableColumn in
            TableColumn(
                key: col["key"] as? String ?? "",
                label: col["label"] as? String ?? "",
                sortable: col["sortable"] as? Bool ?? true,
                format: ValueFormat(rawValue: col["format"] as? String ?? "plain") ?? .plain
            )
        }

        return .table(columns: columns, rows: rows)
    }

    // MARK: - Composite

    private static func parseComposite(_ dict: [String: Any]) -> RenderInput? {
        guard let layoutStr = dict["layout"] as? String,
              let layout = CompositeLayout(rawValue: layoutStr),
              let childrenArray = dict["children"] as? [[String: Any]] else { return nil }

        let children = childrenArray.compactMap { parse($0) }
        guard !children.isEmpty else { return nil }

        return .composite(layout: layout, children: children)
    }
}
