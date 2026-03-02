import Testing
@testable import WheelBrowser

@Suite("HarmonyFormatParser Tests")
struct HarmonyFormatParserTests {

    // MARK: - findJSONEnd: brace counting with strings

    @Test("findJSONEnd handles simple JSON object")
    func findJSONEndSimple() {
        let str = #"{"action":"click","id":5}"#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == str.endIndex)
    }

    @Test("findJSONEnd skips braces inside strings")
    func findJSONEndBracesInString() {
        let str = #"{"thought":"Click the {button} element","action":"click"}"#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == str.endIndex)
    }

    @Test("findJSONEnd handles escaped quotes inside strings")
    func findJSONEndEscapedQuotes() {
        let str = #"{"thought":"He said \"hello\"","action":"done"}"#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == str.endIndex)
    }

    @Test("findJSONEnd handles nested objects")
    func findJSONEndNested() {
        let str = #"{"a":{"b":{"c":1}}}"#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == str.endIndex)
    }

    @Test("findJSONEnd handles nested braces in strings within nested objects")
    func findJSONEndComplexNesting() {
        let str = #"{"thought":"Use {curly} braces","data":{"key":"{val}"}}"#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == str.endIndex)
    }

    @Test("findJSONEnd returns nil for unclosed JSON")
    func findJSONEndUnclosed() {
        let str = #"{"action":"click""#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == nil)
    }

    @Test("findJSONEnd returns nil when not starting with brace")
    func findJSONEndNoBrace() {
        let str = "hello"
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end == nil)
    }

    @Test("findJSONEnd stops at first complete object with trailing text")
    func findJSONEndWithTrailing() {
        let str = #"{"a":1} extra text"#
        let end = HarmonyFormatParser.findJSONEnd(in: str, from: str.startIndex)
        #expect(end != nil)
        if let end = end {
            let extracted = String(str[str.startIndex..<end])
            #expect(extracted == #"{"a":1}"#)
        }
    }

    // MARK: - parse: Harmony format with braces in thought text

    @Test("parse handles thought with curly braces in string values")
    func parseThoughtWithBraces() {
        let response = """
        <|message|>{"thought":"I see a {button} labeled 'Submit'","action":"click(5)"}
        """
        let result = HarmonyFormatParser.parse(response)
        #expect(result != nil)
        #expect(result?.thought.contains("{button}") == true)
        #expect(result?.action == .click(elementId: 5))
    }

    // MARK: - parseToolCall: scroll direction

    @Test("browser.scroll with JSON direction field picks correct direction")
    func scrollDirectionJSON() {
        let response = #"browser.scroll {"direction": "up"}"#
        let action = HarmonyFormatParser.parseToolCall(response)
        #expect(action == .scroll(direction: .up))
    }

    @Test("browser.scroll does not match bare 'down' in natural language")
    func scrollNoFalsePositiveDown() {
        // This response contains "down" in natural text but no quoted direction
        let response = "browser.scroll I'll scroll down to see"
        let action = HarmonyFormatParser.parseToolCall(response)
        // Without a quoted direction, should return nil (no false positive)
        #expect(action == nil)
    }

    @Test("browser.scroll matches quoted 'down' direction")
    func scrollQuotedDown() {
        let response = #"browser.scroll {"direction": "down"}"#
        let action = HarmonyFormatParser.parseToolCall(response)
        #expect(action == .scroll(direction: .down))
    }

    @Test("browser.scroll matches quoted 'top' direction")
    func scrollQuotedTop() {
        let response = #"browser.scroll {"direction": "top"}"#
        let action = HarmonyFormatParser.parseToolCall(response)
        #expect(action == .scroll(direction: .top))
    }

    @Test("browser.scroll matches quoted 'bottom' direction")
    func scrollQuotedBottom() {
        let response = #"browser.scroll {"direction": "bottom"}"#
        let action = HarmonyFormatParser.parseToolCall(response)
        #expect(action == .scroll(direction: .bottom))
    }

    @Test("browser.scroll with only quoted value falls back correctly")
    func scrollFallbackQuoted() {
        let response = #"browser.scroll "up""#
        let action = HarmonyFormatParser.parseToolCall(response)
        #expect(action == .scroll(direction: .up))
    }
}
