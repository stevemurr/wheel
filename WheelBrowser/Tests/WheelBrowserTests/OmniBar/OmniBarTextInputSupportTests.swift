import Testing
@testable import WheelBrowser

@Suite("OmniBar Text Input Support")
struct OmniBarTextInputSupportTests {
    @Test("Mention parser extracts a trailing query after whitespace or start of input")
    func mentionParserFindsValidQueries() {
        #expect(OmniBarMentionTriggerParser.query(in: "@hist") == "hist")
        #expect(OmniBarMentionTriggerParser.query(in: "ask @read") == "read")
    }

    @Test("Mention parser ignores inline at-signs and completed mentions")
    func mentionParserRejectsInvalidTriggers() {
        #expect(OmniBarMentionTriggerParser.query(in: "email@test.com") == nil)
        #expect(OmniBarMentionTriggerParser.query(in: "@done now") == nil)
    }
}
