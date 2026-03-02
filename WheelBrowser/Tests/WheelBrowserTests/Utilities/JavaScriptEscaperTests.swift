import Testing
@testable import WheelBrowser

@Suite("JavaScriptEscaper Tests")
struct JavaScriptEscaperTests {

    // MARK: - Individual escape sequences

    @Test("Escapes backslashes")
    func escapesBackslashes() {
        let result = JavaScriptEscaper.escape(#"hello\world"#)
        #expect(result == #"hello\\world"#)
    }

    @Test("Escapes double quotes")
    func escapesDoubleQuotes() {
        let result = JavaScriptEscaper.escape(#"say "hello""#)
        #expect(result == #"say \"hello\""#)
    }

    @Test("Escapes single quotes")
    func escapesSingleQuotes() {
        let result = JavaScriptEscaper.escape("it's")
        #expect(result == "it\\'s")
    }

    @Test("Escapes backticks")
    func escapesBackticks() {
        let result = JavaScriptEscaper.escape("use `code` here")
        #expect(result == "use \\`code\\` here")
    }

    @Test("Escapes dollar signs")
    func escapesDollarSigns() {
        let result = JavaScriptEscaper.escape("cost $5")
        #expect(result == "cost \\$5")
    }

    @Test("Escapes newlines")
    func escapesNewlines() {
        let result = JavaScriptEscaper.escape("line1\nline2")
        #expect(result == "line1\\nline2")
    }

    @Test("Escapes carriage returns")
    func escapesCarriageReturns() {
        let result = JavaScriptEscaper.escape("line1\rline2")
        #expect(result == "line1\\rline2")
    }

    @Test("Escapes tabs")
    func escapesTabs() {
        let result = JavaScriptEscaper.escape("col1\tcol2")
        #expect(result == "col1\\tcol2")
    }

    @Test("Strips null bytes")
    func stripsNullBytes() {
        let result = JavaScriptEscaper.escape("hello\0world")
        #expect(result == "helloworld")
    }

    @Test("Escapes Unicode line separator U+2028")
    func escapesLineSeparator() {
        let result = JavaScriptEscaper.escape("before\u{2028}after")
        #expect(result == "before\\u2028after")
    }

    @Test("Escapes Unicode paragraph separator U+2029")
    func escapesParagraphSeparator() {
        let result = JavaScriptEscaper.escape("before\u{2029}after")
        #expect(result == "before\\u2029after")
    }

    // MARK: - Ordering and combinations

    @Test("Backslash escaped before other characters")
    func backslashEscapedFirst() {
        // Input: backslash followed by n (not a newline)
        // Should become: \\n (escaped backslash + literal n)
        // NOT: \n (which would be interpreted as newline in JS)
        let result = JavaScriptEscaper.escape(#"\n"#)
        #expect(result == #"\\n"#)
    }

    @Test("Multiple special characters in one string")
    func multipleSpecialChars() {
        let result = JavaScriptEscaper.escape("He said \"it's $5\"\nOK")
        #expect(result == "He said \\\"it\\'s \\$5\\\"\\nOK")
    }

    @Test("Template literal injection prevention")
    func templateLiteralInjection() {
        let result = JavaScriptEscaper.escape("${alert(1)}")
        #expect(result == "\\${alert(1)}")
    }

    // MARK: - Edge cases

    @Test("Empty string returns empty")
    func emptyString() {
        let result = JavaScriptEscaper.escape("")
        #expect(result == "")
    }

    @Test("Safe string passes through unchanged")
    func safeStringUnchanged() {
        let result = JavaScriptEscaper.escape("hello world 123")
        #expect(result == "hello world 123")
    }

    @Test("Unicode text passes through unchanged")
    func unicodePassthrough() {
        let result = JavaScriptEscaper.escape("日本語テスト")
        #expect(result == "日本語テスト")
    }

    @Test("Emoji passes through unchanged")
    func emojiPassthrough() {
        let result = JavaScriptEscaper.escape("Hello 👋 World 🌍")
        #expect(result == "Hello 👋 World 🌍")
    }

    @Test("All special characters combined")
    func allSpecialCharsCombined() {
        let input = "\\\"\'\n\r\t\0`$\u{2028}\u{2029}"
        let result = JavaScriptEscaper.escape(input)
        #expect(result == "\\\\\\\"\\'\\n\\r\\t\\`\\$\\u2028\\u2029")
    }

    @Test("Consecutive backslashes")
    func consecutiveBackslashes() {
        let result = JavaScriptEscaper.escape(#"\\"#)
        #expect(result == #"\\\\"#)
    }
}
