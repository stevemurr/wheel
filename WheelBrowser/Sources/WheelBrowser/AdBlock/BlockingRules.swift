import Foundation

// MARK: - Blocking Categories

/// Categories of content blocking rules that can be individually enabled/disabled
enum BlockingCategory: String, CaseIterable, Codable {
    case ads = "ads"
    case trackers = "trackers"
    case socialWidgets = "social"
    case annoyances = "annoyances"

    var displayName: String {
        switch self {
        case .ads: return "Ads"
        case .trackers: return "Trackers"
        case .socialWidgets: return "Social Widgets"
        case .annoyances: return "Annoyances"
        }
    }

    var description: String {
        switch self {
        case .ads:
            return "Block advertisements from major ad networks"
        case .trackers:
            return "Block analytics and tracking scripts"
        case .socialWidgets:
            return "Block social media widgets and share buttons"
        case .annoyances:
            return "Block cookie banners, newsletter popups, and other annoyances"
        }
    }

    var icon: String {
        switch self {
        case .ads: return "rectangle.slash"
        case .trackers: return "eye.slash"
        case .socialWidgets: return "person.2.slash"
        case .annoyances: return "xmark.rectangle"
        }
    }
}

// MARK: - Blocking Rules

/// Content blocking rules in WebKit's JSON format, loaded from bundled JSON resources.
/// Reference: https://developer.apple.com/documentation/safariservices/creating_a_content_blocker
struct BlockingRules {

    /// Rule set identifier for WebKit's cache
    static let ruleSetIdentifier = "WheelBrowserBlockingRules"

    /// Version for cache invalidation - increment when rules change
    static let ruleSetVersion = "2.1.0"

    // MARK: - Rule Generation

    /// Generates combined JSON rules for the specified categories
    /// - Parameter categories: Set of categories to include
    /// - Returns: JSON string of combined rules
    static func generateRulesJSON(for categories: Set<BlockingCategory>) -> String {
        var allRules: [[String: Any]] = []

        for category in categories {
            allRules.append(contentsOf: rules(for: category))
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: allRules, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }

        return jsonString
    }

    /// Returns rules for a specific category
    static func rules(for category: BlockingCategory) -> [[String: Any]] {
        loadRules(named: category.rawValue)
    }

    /// Returns combined rules for a set of categories
    static func rules(for categories: Set<BlockingCategory>) -> [[String: Any]] {
        var allRules: [[String: Any]] = []
        for category in categories {
            allRules.append(contentsOf: rules(for: category))
        }
        return allRules
    }

    /// Default rules JSON (all categories enabled)
    static var defaultRulesJSON: String {
        generateRulesJSON(for: Set(BlockingCategory.allCases))
    }

    // MARK: - JSON Loading

    /// Cache loaded rules to avoid repeated disk I/O
    private static var cache: [String: [[String: Any]]] = [:]

    /// Load rules from a bundled JSON file
    private static func loadRules(named name: String) -> [[String: Any]] {
        if let cached = cache[name] { return cached }

        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "BlockingRules"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            Log.AdBlock.error("Failed to load blocking rules from \(name).json")
            return []
        }

        cache[name] = rules
        return rules
    }
}
