import Foundation

struct ParsedChatFollowUpSuggestions: Equatable, Sendable {
    let displayText: String
    let suggestions: [String]
}

enum ChatFollowUpSuggestionParser {
    static func parse(_ responseText: String) -> ParsedChatFollowUpSuggestions {
        let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedResponse.isEmpty == false else {
            return ParsedChatFollowUpSuggestions(displayText: "", suggestions: [])
        }

        let lines = trimmedResponse
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)

        guard let section = trailingFollowUpSection(in: lines) else {
            return ParsedChatFollowUpSuggestions(displayText: trimmedResponse, suggestions: [])
        }

        let displayText = Array(lines[..<section.headingIndex])
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestions = FollowUpSuggestionNormalizer.normalize(section.suggestions)

        guard displayText.isEmpty == false, suggestions.isEmpty == false else {
            return ParsedChatFollowUpSuggestions(displayText: trimmedResponse, suggestions: [])
        }

        return ParsedChatFollowUpSuggestions(
            displayText: displayText,
            suggestions: suggestions
        )
    }

    private struct TrailingFollowUpSection {
        let headingIndex: Int
        let suggestions: [String]
    }

    private static func trailingFollowUpSection(in lines: [String]) -> TrailingFollowUpSection? {
        guard lines.isEmpty == false else {
            return nil
        }

        var index = lines.count - 1
        var suggestionsReversed: [String] = []

        while index >= 0 {
            let trimmedLine = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmedLine.isEmpty == false else {
                break
            }
            guard isSuggestionLine(trimmedLine) else {
                break
            }

            suggestionsReversed.append(trimmedLine)
            index -= 1
        }

        guard suggestionsReversed.isEmpty == false else {
            return nil
        }

        while index >= 0, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index -= 1
        }

        guard index >= 0 else {
            return nil
        }

        let headingLine = lines[index].trimmingCharacters(in: .whitespaces)
        guard isFollowUpHeading(headingLine) else {
            return nil
        }

        return TrailingFollowUpSection(
            headingIndex: index,
            suggestions: Array(suggestionsReversed.reversed())
        )
    }

    private static func isSuggestionLine(_ line: String) -> Bool {
        let bulletPattern = #"^[-*•]\s+\S+"#
        let numberedPattern = #"^\d+\.\s+\S+"#

        return line.range(of: bulletPattern, options: .regularExpression) != nil
            || line.range(of: numberedPattern, options: .regularExpression) != nil
    }

    private static func isFollowUpHeading(_ line: String) -> Bool {
        let normalized = line
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")

        return [
            "follow-up questions",
            "follow up questions",
            "follow-up question",
            "follow up question",
            "next questions",
            "next question",
            "you could also ask",
        ].contains(normalized)
    }
}
