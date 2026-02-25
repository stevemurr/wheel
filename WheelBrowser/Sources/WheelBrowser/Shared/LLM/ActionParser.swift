import Foundation

/// Protocol for parsing LLM responses into structured actions.
/// Implementations can handle different LLM output formats (plain text, JSON, etc.)
public protocol ActionParser {
    associatedtype Action

    /// Parse an LLM response string into a structured action
    /// - Parameter response: The raw LLM response text
    /// - Returns: A tuple of (thought/reasoning, action), or nil if parsing fails
    func parse(_ response: String) -> (thought: String, action: Action)?
}

// MARK: - Thought-Action Response Parser

/// Parser for responses in the THOUGHT/ACTION format commonly used by ReAct agents.
/// Example format:
/// ```
/// THOUGHT: I need to click the search button.
/// ACTION: click(5)
/// ```
public struct ThoughtActionParser<Action>: ActionParser {
    /// Function to parse an action string into the Action type
    private let actionParser: (String) -> Action?

    /// Thought label to look for (default: "THOUGHT:")
    private let thoughtLabel: String

    /// Action label to look for (default: "ACTION:")
    private let actionLabel: String

    /// Creates a new thought-action parser
    /// - Parameters:
    ///   - thoughtLabel: The label that precedes the thought (default: "THOUGHT:")
    ///   - actionLabel: The label that precedes the action (default: "ACTION:")
    ///   - actionParser: Function to convert action string to Action type
    public init(
        thoughtLabel: String = "THOUGHT:",
        actionLabel: String = "ACTION:",
        actionParser: @escaping (String) -> Action?
    ) {
        self.thoughtLabel = thoughtLabel
        self.actionLabel = actionLabel
        self.actionParser = actionParser
    }

    public func parse(_ response: String) -> (thought: String, action: Action)? {
        // Find THOUGHT and ACTION markers (case insensitive)
        guard let thoughtMatch = response.range(of: thoughtLabel, options: .caseInsensitive),
              let actionMatch = response.range(of: actionLabel, options: .caseInsensitive) else {
            return nil
        }

        let thoughtStart = thoughtMatch.upperBound
        let thoughtEnd = actionMatch.lowerBound

        // Ensure THOUGHT comes before ACTION
        guard thoughtEnd > thoughtStart else {
            return nil
        }

        let thought = String(response[thoughtStart..<thoughtEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var actionString = String(response[actionMatch.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle multi-action responses: only parse the FIRST action
        if let nextActionRange = actionString.range(of: #"\n\s*(THOUGHT:|ACTION:)"#, options: .regularExpression) {
            actionString = String(actionString[..<nextActionRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let action = actionParser(actionString) else {
            return nil
        }

        return (thought, action)
    }
}

// MARK: - JSON Action Parser

/// Parser for JSON-formatted LLM responses containing thought and action fields.
/// Example format:
/// ```json
/// {"thought": "I need to click the button", "action": "click(5)"}
/// ```
public struct JSONActionParser<Action>: ActionParser {
    /// Function to parse an action string into the Action type
    private let actionParser: (String) -> Action?

    /// Key for the thought field in JSON (default: "thought")
    private let thoughtKey: String

    /// Key for the action field in JSON (default: "action")
    private let actionKey: String

    /// Creates a new JSON action parser
    /// - Parameters:
    ///   - thoughtKey: The JSON key for the thought field (default: "thought")
    ///   - actionKey: The JSON key for the action field (default: "action")
    ///   - actionParser: Function to convert action string to Action type
    public init(
        thoughtKey: String = "thought",
        actionKey: String = "action",
        actionParser: @escaping (String) -> Action?
    ) {
        self.thoughtKey = thoughtKey
        self.actionKey = actionKey
        self.actionParser = actionParser
    }

    public func parse(_ response: String) -> (thought: String, action: Action)? {
        // Extract JSON from the response
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract thought (optional) and action (required)
        let thought = json[thoughtKey] as? String ?? "(from JSON)"

        guard let actionStr = json[actionKey] as? String,
              let action = actionParser(actionStr) else {
            return nil
        }

        return (thought, action)
    }

    /// Extract JSON object from response text
    private func extractJSON(from response: String) -> String {
        // Look for JSON object by finding { ... }
        if let start = response.firstIndex(of: "{") {
            var braceCount = 0
            for idx in response.indices[start...] {
                if response[idx] == "{" { braceCount += 1 }
                else if response[idx] == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        return String(response[start...idx])
                    }
                }
            }
        }
        return response
    }
}

// MARK: - Composite Parser

/// A parser that tries multiple parsers in sequence until one succeeds.
/// Useful for handling LLMs that may output in different formats.
public struct CompositeActionParser<Action>: ActionParser {
    private let parsers: [(String) -> (thought: String, action: Action)?]

    /// Creates a composite parser from multiple parser implementations
    /// - Parameter parsers: The parsers to try in order
    public init(parsers: [(String) -> (thought: String, action: Action)?]) {
        self.parsers = parsers
    }

    /// Creates a composite parser from ActionParser instances
    public static func from<P1: ActionParser, P2: ActionParser>(
        _ p1: P1,
        _ p2: P2
    ) -> CompositeActionParser<Action> where P1.Action == Action, P2.Action == Action {
        CompositeActionParser(parsers: [p1.parse, p2.parse])
    }

    /// Creates a composite parser from three ActionParser instances
    public static func from<P1: ActionParser, P2: ActionParser, P3: ActionParser>(
        _ p1: P1,
        _ p2: P2,
        _ p3: P3
    ) -> CompositeActionParser<Action> where P1.Action == Action, P2.Action == Action, P3.Action == Action {
        CompositeActionParser(parsers: [p1.parse, p2.parse, p3.parse])
    }

    public func parse(_ response: String) -> (thought: String, action: Action)? {
        for parser in parsers {
            if let result = parser(response) {
                return result
            }
        }
        return nil
    }
}

// MARK: - Regex-Based Action Parsing Helpers

/// Common regex patterns for parsing LLM action strings
public enum ActionPatterns {
    /// Pattern for function call: name(args)
    public static let functionCall = #"(\w+)\s*\((.*?)\)"#

    /// Pattern for click(id)
    public static let click = #"click\s*\(\s*(\d+)\s*\)"#

    /// Pattern for type(id, "text")
    public static let typeAction = #"type\s*\(\s*(\d+)\s*,\s*[\"'](.+?)[\"']\s*\)"#

    /// Pattern for scroll(direction)
    public static let scroll = #"scroll\s*\(\s*(\w+)\s*\)"#

    /// Pattern for navigate("url")
    public static let navigate = #"navigate\s*\(\s*[\"'](.+?)[\"']\s*\)"#

    /// Pattern for done("summary")
    public static let done = #"done\s*\(\s*[\"'](.+?)[\"']\s*\)"#

    /// Extract first regex match from string
    public static func firstMatch(_ pattern: String, in string: String) -> String? {
        guard let range = string.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(string[range])
    }

    /// Extract capture groups from regex match
    public static func captureGroups(_ pattern: String, in string: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: string,
                options: [],
                range: NSRange(string.startIndex..., in: string)
              ) else {
            return nil
        }

        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: i), in: string) {
                groups.append(String(string[range]))
            }
        }
        return groups.isEmpty ? nil : groups
    }
}
