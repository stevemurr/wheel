import Testing
@testable import WheelBrowser

@Suite("Follow-Up Suggestion Parser Tests")
struct FollowUpSuggestionParserTests {

    @Test("Extracts and strips tagged suggestions")
    func extractsTaggedSuggestions() {
        let response = """
        Here is the answer.

        [SUGGESTIONS]
        - What changed recently?
        - Can you summarize the key risks?
        [/SUGGESTIONS]
        """

        let result = FollowUpSuggestionParser.parse(from: response)

        #expect(result.displayContent == "Here is the answer.")
        #expect(result.suggestions == [
            "What changed recently?",
            "Can you summarize the key risks?"
        ])
    }

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

        let normalized = FollowUpSuggestionParser.normalize(suggestions)

        #expect(normalized == [
            "First question?",
            "Second question?",
            "Third question?"
        ])
    }
}
