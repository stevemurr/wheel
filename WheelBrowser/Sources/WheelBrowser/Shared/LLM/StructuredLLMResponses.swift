import Foundation

enum FollowUpSuggestionNormalizer {
    static func normalize(_ suggestions: [String]) -> [String] {
        var seen = Set<String>()

        return suggestions
            .map(cleanSuggestion)
            .filter { !$0.isEmpty }
            .filter { suggestion in
                let inserted = seen.insert(suggestion).inserted
                return inserted
            }
            .prefix(3)
            .map { String($0) }
    }

    private static func cleanSuggestion(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") {
            cleaned = String(cleaned.dropFirst(2))
        }

        if let dotRange = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            cleaned = String(cleaned[dotRange.upperBound...])
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GeneratedChatAssistantResponse: Codable, Sendable, WheelStructuredSpecProviding {
    let answer: String

    let suggestions: [String]

    private enum CodingKeys: String, CodingKey {
        case answer
        case suggestions
    }

    init(answer: String, suggestions: [String]) {
        self.answer = answer
        self.suggestions = suggestions
    }

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let answer = try? container.decode(String.self, forKey: .answer) {
            self.answer = answer
            self.suggestions = Self.decodeSuggestions(from: container)
            return
        }

        if let envelope = try? decoder.container(keyedBy: EnvelopeCodingKeys.self),
           let nested = try? envelope.nestedContainer(keyedBy: CodingKeys.self, forKey: .response),
           let answer = try? nested.decode(String.self, forKey: .answer) {
            self.answer = answer
            self.suggestions = Self.decodeSuggestions(from: nested)
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self),
           container.allKeys.count == 1,
           let key = container.allKeys.first,
           let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: key),
           let answer = try? nested.decode(String.self, forKey: .answer) {
            self.answer = answer
            self.suggestions = Self.decodeSuggestions(from: nested)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decode(String.self, forKey: .answer)
        suggestions = Self.decodeSuggestions(from: container)
    }

    var normalizedSuggestions: [String] {
        FollowUpSuggestionNormalizer.normalize(suggestions)
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedChatAssistantResponse",
        description: "A browser chat response with the answer text and suggested follow-up questions.",
        properties: [
            WheelOutputSchema.property(
                "answer",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "The main assistant answer in markdown."
            ),
            WheelOutputSchema.property(
                "suggestions",
                schema: WheelOutputSchema.array(
                    item: WheelOutputSchema.string(minLength: 1),
                    maximumCount: 3
                ),
                description: "Two or three concise follow-up questions.",
                optional: true
            ),
        ]
    )

    static let spec = structuredSpec { $0.answer }
}

extension GeneratedChatAssistantResponse {
    private enum EnvelopeCodingKeys: String, CodingKey {
        case response
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private static func decodeSuggestions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String] {
        guard let rawSuggestions = try? container.decodeIfPresent(AnyCodable.self, forKey: .suggestions) else {
            return []
        }

        return extractSuggestions(from: rawSuggestions)
    }

    private static func extractSuggestions(from rawSuggestions: AnyCodable) -> [String] {
        if let suggestions = rawSuggestions.arrayValue {
            return suggestions.compactMap(extractSuggestionText(from:))
        }

        if let suggestion = rawSuggestions.stringValue {
            return parseSuggestionsString(suggestion)
        }

        if let suggestion = extractSuggestionText(from: rawSuggestions.value) {
            return [suggestion]
        }

        return []
    }

    private static func extractSuggestionText(from value: Any) -> String? {
        if let suggestion = value as? String {
            return suggestion
        }

        guard let dictionary = value as? [String: Any] else {
            return nil
        }

        for key in ["text", "question", "suggestion", "title"] {
            if let suggestion = dictionary[key] as? String {
                return suggestion
            }
        }

        return nil
    }

    private static func parseSuggestionsString(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return []
        }

        if let data = trimmed.data(using: .utf8),
           let suggestions = try? JSONDecoder().decode([String].self, from: data) {
            return suggestions
        }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { String($0) }

        if lines.count > 1 {
            return lines
        }

        return [trimmed]
    }
}

struct GeneratedSummaryResponse: Codable, Sendable, WheelStructuredSpecProviding {
    let summary: String

    init(summary: String) {
        self.summary = summary
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedSummaryResponse",
        description: "A concise page summary.",
        properties: [
            WheelOutputSchema.property(
                "summary",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "A brief summary in 2-3 sentences and under 100 words."
            ),
        ]
    )

    static let spec = structuredSpec { $0.summary }
}
