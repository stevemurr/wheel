import Foundation
import FoundationModels

protocol FollowUpSuggestionProviding: Sendable {
    func generateSuggestions(userMessage: String, assistantResponse: String) async throws -> [String]
}

enum FollowUpSuggestionParser {
    struct Result: Equatable {
        let displayContent: String
        let suggestions: [String]
    }

    static func parse(from content: String) -> Result {
        Result(
            displayContent: stripSuggestionsBlock(from: content),
            suggestions: extractSuggestions(from: content)
        )
    }

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

    private static func extractSuggestions(from content: String) -> [String] {
        guard let startRange = content.range(of: "[SUGGESTIONS]"),
              let endRange = content.range(of: "[/SUGGESTIONS]") else {
            return []
        }

        let suggestionsText = String(content[startRange.upperBound..<endRange.lowerBound])
        return normalize(suggestionsText.components(separatedBy: .newlines))
    }

    private static func stripSuggestionsBlock(from content: String) -> String {
        guard let startRange = content.range(of: "[SUGGESTIONS]") else { return content }

        if let endRange = content.range(of: "[/SUGGESTIONS]") {
            var result = content
            result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(content[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
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

@Generable(description: "A small set of relevant follow-up questions the user could ask next.")
struct GeneratedFollowUpSuggestions: Sendable {
    @Guide(description: "Two or three concise follow-up questions phrased exactly as the user could ask them.")
    let suggestions: [String]
}

struct OnDeviceFollowUpSuggestionProvider: FollowUpSuggestionProviding {
    func generateSuggestions(userMessage: String, assistantResponse: String) async throws -> [String] {
        let prompt = """
        User message:
        \(userMessage)

        Assistant response:
        \(assistantResponse)
        """

        let result = try await OnDeviceLLM.shared.complete(
            prompt: prompt,
            instructions: SystemPromptConfig.followUpSuggestionPrompt,
            generating: GeneratedFollowUpSuggestions.self
        )

        return FollowUpSuggestionParser.normalize(result.suggestions)
    }
}
