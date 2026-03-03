import Foundation

/// The output of a render skill — a typed description of what SwiftUI view to build.
enum RenderInput {
    case list(title: String, items: [ListItem])
    case statCard(label: String, value: String, format: ValueFormat, delta: Delta?)
    case chart(config: ChartConfig)
    case table(columns: [TableColumn], rows: [[String: Any]])
    case composite(layout: CompositeLayout, children: [RenderInput])
}

// MARK: - List Types

struct ListItem {
    let headline: String
    var subheadline: String?
    var badge: Badge?
    var link: String?

    struct Badge {
        let text: String
        let color: BadgeColor

        enum BadgeColor: String {
            case red, orange, green, blue, gray
        }
    }
}

// MARK: - Stat Card Types

enum ValueFormat: String {
    case plain
    case currency
    case percent
    case number
    case temperature
}

struct Delta {
    let value: Double
    let label: String?
}

// MARK: - Chart Types

struct ChartConfig {
    let type: ChartType
    let title: String?
    let data: [[String: Any]]
    let xField: String
    let yField: String
    var seriesField: String?
    var colorScheme: String?

    enum ChartType: String {
        case line, bar, area, candlestick, scatter, pie, doughnut
    }
}

// MARK: - Table Types

struct TableColumn {
    let key: String
    let label: String
    var sortable: Bool = true
    var format: ValueFormat = .plain
}

// MARK: - Composite Types

enum CompositeLayout: String {
    case vstack, hstack, grid2col = "grid_2col"
}
