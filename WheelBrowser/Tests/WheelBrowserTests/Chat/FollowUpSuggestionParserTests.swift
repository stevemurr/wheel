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

    @Test("Parses a trailing follow-up section and strips it from the display text")
    func parsesTrailingFollowUpSection() {
        let parsed = ChatFollowUpSuggestionParser.parse(
            """
            Here is the main answer.

            Follow-up questions:
            - First follow-up?
            - Second follow-up?
            """
        )

        #expect(parsed.displayText == "Here is the main answer.")
        #expect(parsed.suggestions == [
            "First follow-up?",
            "Second follow-up?",
        ])
    }

    @Test("Leaves ordinary prose untouched when no trailing follow-up section exists")
    func leavesOrdinaryProseUntouched() {
        let parsed = ChatFollowUpSuggestionParser.parse(
            """
            Here is the answer.

            - This is just a list in the answer.
            - It should stay in the answer body.
            """
        )

        #expect(parsed.displayText == """
        Here is the answer.

        - This is just a list in the answer.
        - It should stay in the answer body.
        """)
        #expect(parsed.suggestions.isEmpty)
    }

    @Test("Ignores follow-up headings that are not at the end of the answer")
    func ignoresMidAnswerFollowUpSection() {
        let parsed = ChatFollowUpSuggestionParser.parse(
            """
            Summary first.

            Follow-up questions:
            - First follow-up?

            Final note after the section.
            """
        )

        #expect(parsed.displayText == """
        Summary first.

        Follow-up questions:
        - First follow-up?

        Final note after the section.
        """)
        #expect(parsed.suggestions.isEmpty)
    }
}
