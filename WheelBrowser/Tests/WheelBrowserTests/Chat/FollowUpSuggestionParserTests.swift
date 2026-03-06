import Testing
@testable import WheelBrowser

@Suite("Follow-Up Suggestion Normalizer Tests")
struct FollowUpSuggestionParserTests {

    @Test("Normalizes bullets, numbering, duplicates, and blanks")
    func normalizesSuggestions() {
        let suggestions = [
            "  - First question?  ",
            "1. Second question?",
            "",
            "Second question?",
            "* Third question?",
            "Fourth question?"
        ]

        let normalized = FollowUpSuggestionNormalizer.normalize(suggestions)

        #expect(normalized == [
            "First question?",
            "Second question?",
            "Third question?"
        ])
    }

    @Test("Structured chat responses expose normalized suggestions")
    func normalizedSuggestionsFromStructuredResponse() {
        let response = GeneratedChatAssistantResponse(
            answer: "Here is the answer.",
            suggestions: [
                "- First follow-up?",
                "Second follow-up?",
                "Second follow-up?"
            ]
        )

        #expect(response.normalizedSuggestions == [
            "First follow-up?",
            "Second follow-up?"
        ])
    }
}
