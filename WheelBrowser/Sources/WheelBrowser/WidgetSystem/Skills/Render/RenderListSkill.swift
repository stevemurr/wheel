import Foundation

/// Converts pipeline data into a `RenderInput.list` for display.
struct RenderListSkill: WidgetSkill {
    let name = SkillName.renderList

    let paramSchema = """
    {
      "title": "string (optional) — list title",
      "headline_field": "string (required) — field name for the main text",
      "subheadline_field": "string (optional) — field name for secondary text",
      "badge_field": "string (optional) — field name for badge text",
      "badge_color": "string (optional, default 'gray') — one of: red, orange, green, blue, gray",
      "link_field": "string (optional) — field name for the clickable URL",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let input = (params["input"] as? [[String: Any]]) ?? []
        let title = (params["title"] as? String) ?? ""
        let headlineField = (params["headline_field"] as? String) ?? "headline"
        let subheadlineField = params["subheadline_field"] as? String
        let badgeField = params["badge_field"] as? String
        let badgeColorRaw = (params["badge_color"] as? String) ?? "gray"
        let badgeColor = ListItem.Badge.BadgeColor(rawValue: badgeColorRaw) ?? .gray
        let linkField = params["link_field"] as? String

        let items = input.map { row -> ListItem in
            let headline = stringValue(row[headlineField])
            let subheadline = subheadlineField.flatMap { row[$0] }.map { stringValue($0) }
            let badge: ListItem.Badge? = badgeField.flatMap { row[$0] }.map {
                ListItem.Badge(text: stringValue($0), color: badgeColor)
            }
            let link = linkField.flatMap { row[$0] } as? String

            return ListItem(headline: headline, subheadline: subheadline, badge: badge, link: link)
        }

        return RenderInput.list(title: title, items: items)
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if let n = value as? Int { return "\(n)" }
        if let d = value as? Double { return String(format: "%.2f", d) }
        return "\(value)"
    }
}
