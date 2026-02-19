import Foundation

/// Persisted configuration for a single widget instance
struct WidgetInstanceConfig: Codable, Identifiable {
    let id: UUID
    let typeIdentifier: String
    var size: WidgetSize
    var position: Int  // Order in the grid
    var customData: [String: AnyCodable]

    init(
        id: UUID = UUID(),
        typeIdentifier: String,
        size: WidgetSize = .medium,
        position: Int = 0,
        customData: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.typeIdentifier = typeIdentifier
        self.size = size
        self.position = position
        self.customData = customData
    }
}

/// Overall new tab page configuration
struct NewTabPageConfig: Codable {
    var widgets: [WidgetInstanceConfig]
    var showGreeting: Bool
    var backgroundStyle: BackgroundStyle

    init(
        widgets: [WidgetInstanceConfig] = [],
        showGreeting: Bool = true,
        backgroundStyle: BackgroundStyle = .system
    ) {
        self.widgets = widgets
        self.showGreeting = showGreeting
        self.backgroundStyle = backgroundStyle
    }

    enum BackgroundStyle: String, Codable, CaseIterable {
        case system
        case dark
        case light

        var displayName: String {
            switch self {
            case .system: return "System"
            case .dark: return "Dark"
            case .light: return "Light"
            }
        }
    }

    /// Default configuration with starter widgets
    static var defaultConfig: NewTabPageConfig {
        NewTabPageConfig(
            widgets: [
                WidgetInstanceConfig(typeIdentifier: "search", size: .wide, position: 0),
                WidgetInstanceConfig(typeIdentifier: "quickLinks", size: .medium, position: 1),
                WidgetInstanceConfig(typeIdentifier: "recentHistory", size: .medium, position: 2),
            ],
            showGreeting: true,
            backgroundStyle: .system
        )
    }
}

/// Type-erased Codable wrapper for storing arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unable to encode AnyCodable"))
        }
    }
}
