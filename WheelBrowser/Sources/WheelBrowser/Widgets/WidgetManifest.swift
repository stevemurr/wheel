import Foundation

enum WidgetType: String, Codable, CaseIterable, Sendable {
    case barChart
    case lineChart
    case statCard
    case table
    case list
    case text
    case priceCard
}

enum WidgetSkillName: String, Codable, CaseIterable, Sendable {
    case currentDateTime
    case fetchUrl
    case parseHtml
    case parseJson
    case extractWithRegex
    case parseCsv
    case transform
    case filterSort
    case mergeArrays
    case computeStats
}

struct WidgetSkillStep: Codable, Sendable {
    let step: Int
    let skill: WidgetSkillName
    let params: [String: AnyCodable]
    let outputKey: String
}

struct WidgetManifest: Codable, Identifiable, Sendable {
    let id: UUID
    let version: String
    let widgetType: WidgetType
    let config: WidgetConfig
    let skillChain: [WidgetSkillStep]
    let returns: String
    let ttl: Int
    let prompt: String

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case widgetType
        case config
        case skillChain
        case returns
        case ttl
        case prompt
    }

    init(
        id: UUID = UUID(),
        version: String = "1",
        widgetType: WidgetType,
        config: WidgetConfig,
        skillChain: [WidgetSkillStep],
        returns: String,
        ttl: Int,
        prompt: String
    ) {
        self.id = id
        self.version = version
        self.widgetType = widgetType
        self.config = config
        self.skillChain = skillChain
        self.returns = returns
        self.ttl = ttl
        self.prompt = prompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        version = try container.decode(String.self, forKey: .version)
        widgetType = try container.decode(WidgetType.self, forKey: .widgetType)
        config = try WidgetConfig.decode(
            from: container.superDecoder(forKey: .config),
            widgetType: widgetType
        )
        skillChain = try container.decode([WidgetSkillStep].self, forKey: .skillChain)
        returns = try container.decode(String.self, forKey: .returns)
        ttl = try container.decode(Int.self, forKey: .ttl)
        prompt = try container.decode(String.self, forKey: .prompt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(version, forKey: .version)
        try container.encode(widgetType, forKey: .widgetType)
        try config.encode(to: container.superEncoder(forKey: .config))
        try container.encode(skillChain, forKey: .skillChain)
        try container.encode(returns, forKey: .returns)
        try container.encode(ttl, forKey: .ttl)
        try container.encode(prompt, forKey: .prompt)
    }

    var allowedHosts: Set<String> {
        Set(
            skillChain.compactMap { step in
                guard step.skill == .fetchUrl,
                      let rawURL = step.params["url"]?.stringValue,
                      let url = URL(string: rawURL),
                      let host = url.host?.lowercased() else {
                    return nil
                }
                return host
            }
        )
    }
}

enum WidgetConfig: Sendable {
    case barChart(BarChartConfig)
    case lineChart(LineChartConfig)
    case statCard(StatCardConfig)
    case table(TableConfig)
    case list(ListConfig)
    case text(TextConfig)
    case priceCard(PriceCardConfig)

    static func decode(from decoder: Decoder, widgetType: WidgetType) throws -> WidgetConfig {
        switch widgetType {
        case .barChart:
            return .barChart(try BarChartConfig(from: decoder))
        case .lineChart:
            return .lineChart(try LineChartConfig(from: decoder))
        case .statCard:
            return .statCard(try StatCardConfig(from: decoder))
        case .table:
            return .table(try TableConfig(from: decoder))
        case .list:
            return .list(try ListConfig(from: decoder))
        case .text:
            return .text(try TextConfig(from: decoder))
        case .priceCard:
            return .priceCard(try PriceCardConfig(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .barChart(let config):
            try config.encode(to: encoder)
        case .lineChart(let config):
            try config.encode(to: encoder)
        case .statCard(let config):
            try config.encode(to: encoder)
        case .table(let config):
            try config.encode(to: encoder)
        case .list(let config):
            try config.encode(to: encoder)
        case .text(let config):
            try config.encode(to: encoder)
        case .priceCard(let config):
            try config.encode(to: encoder)
        }
    }
}

struct BarChartConfig: Codable, Sendable {
    let title: String
    let xField: String
    let yField: String
    let color: String?
    let yPrefix: String?
    let yUnit: String?
}

struct LineChartSeries: Codable, Sendable {
    let field: String
    let label: String
    let color: String?
}

struct LineChartConfig: Codable, Sendable {
    let title: String
    let xField: String
    let series: [LineChartSeries]
    let yPrefix: String?
    let showPoints: Bool?
}

struct StatCardConfig: Codable, Sendable {
    let title: String
    let valueField: String
    let prefix: String?
    let suffix: String?
    let changeField: String?
    let changeIsPercent: Bool?
}

struct TableColumnConfig: Codable, Sendable {
    let field: String
    let header: String
    let prefix: String?
}

struct TableConfig: Codable, Sendable {
    let title: String
    let columns: [TableColumnConfig]
    let maxRows: Int?
}

struct ListConfig: Codable, Sendable {
    let title: String
    let labelField: String
    let valueField: String?
    let iconField: String?
    let maxItems: Int?
}

struct TextConfig: Codable, Sendable {
    let title: String?
    let markdown: Bool
}

struct PriceCardConfig: Codable, Sendable {
    let title: String
    let priceField: String
    let changeField: String?
    let changePercentField: String?
    let prefix: String?
    let footnote: String?
}

struct WidgetRecord: Codable, Identifiable, Sendable {
    var manifest: WidgetManifest
    var position: Int
    var lastLoadedAt: Date?
    var lastError: String?

    var id: UUID { manifest.id }
}
