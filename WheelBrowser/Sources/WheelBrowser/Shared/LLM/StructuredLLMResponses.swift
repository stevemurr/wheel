import Foundation
import FoundationModels

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

@Generable(description: "A browser chat response with the answer text and suggested follow-up questions.")
struct GeneratedChatAssistantResponse: Sendable {
    @Guide(description: "The main assistant answer in markdown. Do not include follow-up suggestions in this field.")
    let answer: String

    @Guide(description: "Two or three concise follow-up questions the user could naturally ask next.")
    let suggestions: [String]

    init(answer: String, suggestions: [String]) {
        self.answer = answer
        self.suggestions = suggestions
    }

    var normalizedSuggestions: [String] {
        FollowUpSuggestionNormalizer.normalize(suggestions)
    }
}

@Generable(description: "A concise page summary.")
struct GeneratedSummaryResponse: Sendable {
    @Guide(description: "A brief summary in 2-3 sentences and under 100 words.")
    let summary: String

    init(summary: String) {
        self.summary = summary
    }
}
