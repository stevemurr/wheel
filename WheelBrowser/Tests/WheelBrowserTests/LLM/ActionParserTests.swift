import Testing
@testable import WheelBrowser

@Suite("ActionParser Tests")
struct ActionParserTests {

    // MARK: - ThoughtActionParser Tests

    @Suite("ThoughtActionParser")
    struct ThoughtActionParserTests {

        @Test("Parses valid THOUGHT/ACTION format")
        func parsesValidFormat() {
            let parser = ThoughtActionParser<String>(actionParser: { $0 })

            let response = """
            THOUGHT: I need to click the button.
            ACTION: click(5)
            """

            let result = parser.parse(response)

            #expect(result != nil)
            #expect(result?.thought == "I need to click the button.")
            #expect(result?.action == "click(5)")
        }

        @Test("Parses case-insensitive labels")
        func parsesCaseInsensitive() {
            let parser = ThoughtActionParser<String>(actionParser: { $0 })

            let response = """
            thought: thinking here
            action: do_something()
            """

            let result = parser.parse(response)

            #expect(result != nil)
            #expect(result?.thought == "thinking here")
            #expect(result?.action == "do_something()")
        }

        @Test("Returns nil for missing THOUGHT label")
        func nilForMissingThought() {
            let parser = ThoughtActionParser<String>(actionParser: { $0 })

            let response = "ACTION: click(5)"

            #expect(parser.parse(response) == nil)
        }

        @Test("Returns nil for missing ACTION label")
        func nilForMissingAction() {
            let parser = ThoughtActionParser<String>(actionParser: { $0 })

            let response = "THOUGHT: I need to click."

            #expect(parser.parse(response) == nil)
        }

        @Test("Returns nil when ACTION comes before THOUGHT")
        func nilWhenActionBeforeThought() {
            let parser = ThoughtActionParser<String>(actionParser: { $0 })

            let response = """
            ACTION: click(5)
            THOUGHT: I clicked.
            """

            #expect(parser.parse(response) == nil)
        }

        @Test("Returns nil when action parser fails")
        func nilWhenActionParserFails() {
            let parser = ThoughtActionParser<String>(actionParser: { _ in nil })

            let response = """
            THOUGHT: thinking
            ACTION: invalid
            """

            #expect(parser.parse(response) == nil)
        }

        @Test("Handles multi-action responses by parsing first action only")
        func handlesMultiActionResponse() {
            let parser = ThoughtActionParser<String>(actionParser: { $0 })

            let response = """
            THOUGHT: First thought
            ACTION: first_action()
            THOUGHT: Second thought
            ACTION: second_action()
            """

            let result = parser.parse(response)

            #expect(result?.action == "first_action()")
        }

        @Test("Custom labels work")
        func customLabels() {
            let parser = ThoughtActionParser<String>(
                thoughtLabel: "REASONING:",
                actionLabel: "COMMAND:",
                actionParser: { $0 }
            )

            let response = """
            REASONING: I should do this.
            COMMAND: execute()
            """

            let result = parser.parse(response)

            #expect(result?.thought == "I should do this.")
            #expect(result?.action == "execute()")
        }
    }

    // MARK: - JSONActionParser Tests

    @Suite("JSONActionParser")
    struct JSONActionParserTests {

        @Test("Parses valid JSON format")
        func parsesValidJSON() {
            let parser = JSONActionParser<String>(actionParser: { $0 })

            let response = """
            {"thought": "I need to click", "action": "click(5)"}
            """

            let result = parser.parse(response)

            #expect(result != nil)
            #expect(result?.thought == "I need to click")
            #expect(result?.action == "click(5)")
        }

        @Test("Extracts JSON from surrounding text")
        func extractsJSONFromText() {
            let parser = JSONActionParser<String>(actionParser: { $0 })

            let response = """
            Here is my response:
            {"thought": "thinking", "action": "do_it()"}
            That's my action.
            """

            let result = parser.parse(response)

            #expect(result?.thought == "thinking")
            #expect(result?.action == "do_it()")
        }

        @Test("Uses default thought when thought key missing")
        func defaultThoughtWhenMissing() {
            let parser = JSONActionParser<String>(actionParser: { $0 })

            let response = """
            {"action": "click(5)"}
            """

            let result = parser.parse(response)

            #expect(result?.thought == "(from JSON)")
            #expect(result?.action == "click(5)")
        }

        @Test("Returns nil for missing action key")
        func nilForMissingAction() {
            let parser = JSONActionParser<String>(actionParser: { $0 })

            let response = """
            {"thought": "just thinking"}
            """

            #expect(parser.parse(response) == nil)
        }

        @Test("Returns nil for invalid JSON")
        func nilForInvalidJSON() {
            let parser = JSONActionParser<String>(actionParser: { $0 })

            let response = "not valid json at all"

            #expect(parser.parse(response) == nil)
        }

        @Test("Returns nil when action parser fails")
        func nilWhenActionParserFails() {
            let parser = JSONActionParser<String>(actionParser: { _ in nil })

            let response = """
            {"thought": "thinking", "action": "invalid"}
            """

            #expect(parser.parse(response) == nil)
        }

        @Test("Custom keys work")
        func customKeys() {
            let parser = JSONActionParser<String>(
                thoughtKey: "reasoning",
                actionKey: "command",
                actionParser: { $0 }
            )

            let response = """
            {"reasoning": "I should do this", "command": "execute()"}
            """

            let result = parser.parse(response)

            #expect(result?.thought == "I should do this")
            #expect(result?.action == "execute()")
        }

        @Test("Handles nested braces correctly")
        func handlesNestedBraces() {
            let parser = JSONActionParser<String>(actionParser: { $0 })

            let response = """
            {"thought": "nested {braces}", "action": "click(5)"}
            """

            let result = parser.parse(response)

            #expect(result?.thought == "nested {braces}")
        }
    }

    // MARK: - CompositeActionParser Tests

    @Suite("CompositeActionParser")
    struct CompositeActionParserTests {

        @Test("Tries parsers in order and returns first success")
        func triesInOrder() {
            let failingParser: (String) -> (thought: String, action: String)? = { _ in nil }
            let successfulParser: (String) -> (thought: String, action: String)? = { _ in ("thought", "action") }

            let composite = CompositeActionParser<String>(parsers: [failingParser, successfulParser])

            let result = composite.parse("anything")

            #expect(result?.thought == "thought")
            #expect(result?.action == "action")
        }

        @Test("Returns nil if all parsers fail")
        func nilIfAllFail() {
            let failingParser1: (String) -> (thought: String, action: String)? = { _ in nil }
            let failingParser2: (String) -> (thought: String, action: String)? = { _ in nil }

            let composite = CompositeActionParser<String>(parsers: [failingParser1, failingParser2])

            #expect(composite.parse("anything") == nil)
        }

        @Test("Creates composite from two ActionParser instances")
        func fromTwoParsers() {
            let thoughtParser = ThoughtActionParser<String>(actionParser: { $0 })
            let jsonParser = JSONActionParser<String>(actionParser: { $0 })

            let composite = CompositeActionParser<String>.from(thoughtParser, jsonParser)

            // Should work with thought/action format
            let thoughtResponse = """
            THOUGHT: thinking
            ACTION: click(1)
            """
            #expect(composite.parse(thoughtResponse)?.action == "click(1)")

            // Should also work with JSON format
            let jsonResponse = """
            {"thought": "thinking", "action": "click(2)"}
            """
            #expect(composite.parse(jsonResponse)?.action == "click(2)")
        }
    }

    // MARK: - ActionPatterns Tests

    @Suite("ActionPatterns")
    struct ActionPatternsTests {

        @Test("firstMatch extracts matching substring")
        func firstMatchExtractsSubstring() {
            let result = ActionPatterns.firstMatch(ActionPatterns.click, in: "I will click(5) now")
            #expect(result == "click(5)")
        }

        @Test("firstMatch returns nil for no match")
        func firstMatchReturnsNilForNoMatch() {
            let result = ActionPatterns.firstMatch(ActionPatterns.click, in: "no click here")
            #expect(result == nil)
        }

        @Test("captureGroups extracts groups from click pattern")
        func captureGroupsClick() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.click, in: "click(42)")
            #expect(groups == ["42"])
        }

        @Test("captureGroups extracts groups from type pattern")
        func captureGroupsType() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.typeAction, in: "type(3, 'hello world')")
            #expect(groups?[0] == "3")
            #expect(groups?[1] == "hello world")
        }

        @Test("captureGroups extracts scroll direction")
        func captureGroupsScroll() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.scroll, in: "scroll(down)")
            #expect(groups == ["down"])
        }

        @Test("captureGroups extracts navigate URL")
        func captureGroupsNavigate() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.navigate, in: "navigate('https://example.com')")
            #expect(groups == ["https://example.com"])
        }

        @Test("captureGroups extracts done message")
        func captureGroupsDone() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.done, in: "done('Task completed')")
            #expect(groups == ["Task completed"])
        }

        @Test("captureGroups returns nil for no match")
        func captureGroupsNilForNoMatch() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.click, in: "no match")
            #expect(groups == nil)
        }

        @Test("functionCall pattern extracts name and args")
        func functionCallPattern() {
            let groups = ActionPatterns.captureGroups(ActionPatterns.functionCall, in: "do_something(arg1, arg2)")
            #expect(groups?[0] == "do_something")
            #expect(groups?[1] == "arg1, arg2")
        }
    }
}
