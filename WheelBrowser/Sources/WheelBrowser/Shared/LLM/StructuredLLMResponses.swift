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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decode(String.self, forKey: .answer)
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
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
