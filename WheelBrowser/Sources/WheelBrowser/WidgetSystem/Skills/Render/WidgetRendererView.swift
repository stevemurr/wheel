import SwiftUI

/// Routes a `RenderInput` to the appropriate SwiftUI view.
struct WidgetRendererView: View {
    let input: RenderInput

    var body: some View {
        switch input {
        case .list(let title, let items):
            ListWidgetView(title: title, items: items)

        case .statCard(let label, let value, let format, let delta):
            StatCardView(label: label, value: value, format: format, delta: delta)

        case .chart(let config):
            ChartWidgetView(config: config)

        case .table(let columns, let rows):
            TableWidgetView(columns: columns, rows: rows)

        case .composite(let layout, let children):
            CompositeWidgetView(layout: layout, children: children)
        }
    }
}
