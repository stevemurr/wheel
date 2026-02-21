import Foundation

/// Configuration schema for AI-generated widgets
struct AIWidgetConfig: Codable, Equatable {
    var name: String
    var description: String
    var iconName: String
    var source: DataSource
    var extraction: ExtractionConfig
    var display: DisplayConfig
    var refresh: RefreshConfig

    /// Placeholder config for widget registration
    static let placeholder = AIWidgetConfig(
        name: "AI Widget",
        description: "AI-generated widget",
        iconName: "sparkles",
        source: DataSource(type: .urlFetch, url: "", headers: [:]),
        extraction: ExtractionConfig(type: .css, selectors: [:]),
        display: DisplayConfig(layout: .list, template: "", itemLimit: 5),
        refresh: RefreshConfig(intervalMinutes: 30, autoRefresh: true)
    )
}

// MARK: - Data Source

struct DataSource: Codable, Equatable {
    var type: SourceType
    var url: String
    var headers: [String: String]
    var localConfig: LocalConfig?

    enum SourceType: String, Codable {
        case urlFetch   // HTML pages with CSS selector extraction
        case jsonApi    // JSON APIs with JSONPath extraction
        case rssFeed    // RSS/Atom feeds with built-in parsing
        case local      // Locally computed content (clocks, timers, etc.)
    }

    init(type: SourceType, url: String, headers: [String: String], localConfig: LocalConfig? = nil) {
        self.type = type
        self.url = url
        self.headers = headers
        self.localConfig = localConfig
    }
}

/// Configuration for locally computed widgets
struct LocalConfig: Codable, Equatable {
    var widgetType: LocalWidgetType
    var parameters: [String: String]

    enum LocalWidgetType: String, Codable {
        case worldClock     // Multiple timezone clocks
        case countdown      // Countdown to a date
        case stopwatch      // Stopwatch/timer
        case dateDisplay    // Current date in various formats
    }
}

// MARK: - Extraction Configuration

struct ExtractionConfig: Codable, Equatable {
    var type: ExtractionType
    var selectors: [String: String]     // For CSS: field name -> CSS selector
    var jsonPaths: [String: String]?    // For JSON: field name -> JSON path
    var itemSelector: String?           // For lists: selector to find each item
    var aiPrompt: String?               // Fallback: prompt for AI to extract content

    enum ExtractionType: String, Codable {
        case css        // Use CSS selectors
        case jsonPath   // Use JSON paths
        case rss        // Built-in RSS parsing
        case aiExtract  // AI-assisted extraction
    }

    init(
        type: ExtractionType,
        selectors: [String: String],
        jsonPaths: [String: String]? = nil,
        itemSelector: String? = nil,
        aiPrompt: String? = nil
    ) {
        self.type = type
        self.selectors = selectors
        self.jsonPaths = jsonPaths
        self.itemSelector = itemSelector
        self.aiPrompt = aiPrompt
    }
}

// MARK: - Display Configuration

struct DisplayConfig: Codable, Equatable {
    var layout: LayoutType
    var template: String            // Markdown template with {{field}} placeholders
    var itemLimit: Int
    var showTitle: Bool
    var accentColor: String?        // Optional hex color

    enum LayoutType: String, Codable {
        case list           // Vertical list of items
        case cards          // Card grid
        case singleValue    // Single prominent value (weather, stocks)
        case markdown       // Raw markdown rendering
    }

    enum CodingKeys: String, CodingKey {
        case layout, template, itemLimit, showTitle, accentColor
    }

    init(
        layout: LayoutType,
        template: String,
        itemLimit: Int = 5,
        showTitle: Bool = true,
        accentColor: String? = nil
    ) {
        self.layout = layout
        self.template = template
        self.itemLimit = itemLimit
        self.showTitle = showTitle
        self.accentColor = accentColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decode(LayoutType.self, forKey: .layout)
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        showTitle = try container.decodeIfPresent(Bool.self, forKey: .showTitle) ?? true
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor)

        // Handle itemLimit being either Int or Bool (malformed data from AI generation)
        if let intValue = try? container.decode(Int.self, forKey: .itemLimit) {
            itemLimit = intValue
        } else if let boolValue = try? container.decode(Bool.self, forKey: .itemLimit) {
            // Convert boolean to default value (AI sometimes generates true/false instead of a number)
            itemLimit = boolValue ? 5 : 0
            print("[DisplayConfig] Warning: itemLimit was Bool(\(boolValue)), converted to \(itemLimit)")
        } else {
            itemLimit = 5  // Default
        }
    }
}

// MARK: - Refresh Configuration

struct RefreshConfig: Codable, Equatable {
    var intervalMinutes: Int
    var autoRefresh: Bool

    init(intervalMinutes: Int = 30, autoRefresh: Bool = true) {
        self.intervalMinutes = intervalMinutes
        self.autoRefresh = autoRefresh
    }
}

// MARK: - Extracted Content

/// Represents content extracted from a data source
struct ExtractedContent: Equatable {
    var items: [ExtractedItem]
    var fetchedAt: Date
    var error: String?

    init(items: [ExtractedItem] = [], fetchedAt: Date = Date(), error: String? = nil) {
        self.items = items
        self.fetchedAt = fetchedAt
        self.error = error
    }

    static let empty = ExtractedContent()
}

/// A single extracted item with field values
struct ExtractedItem: Identifiable, Equatable {
    let id = UUID()
    var fields: [String: String]
    var link: URL?

    init(fields: [String: String] = [:], link: URL? = nil) {
        self.fields = fields
        self.link = link
    }

    static func == (lhs: ExtractedItem, rhs: ExtractedItem) -> Bool {
        lhs.fields == rhs.fields && lhs.link == rhs.link
    }
}
