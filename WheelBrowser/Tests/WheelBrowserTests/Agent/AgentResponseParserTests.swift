import Testing
@testable import WheelBrowser

@Suite("AgentResponseParser Tests")
struct AgentResponseParserTests {

    // MARK: - parseResponse: THOUGHT/ACTION format

    @Test("Parses standard THOUGHT/ACTION format")
    func standardFormat() {
        let response = """
        THOUGHT: I need to click the login button
        ACTION: click(5)
        """
        let result = AgentResponseParser.parseResponse(response)
        #expect(result != nil)
        #expect(result?.thought == "I need to click the login button")
        #expect(result?.action == .click(elementId: 5))
    }

    @Test("Parses THOUGHT/ACTION with multiline thought")
    func multilineThought() {
        let response = """
        THOUGHT: First I'll analyze the page.
        The login form has two fields.
        ACTION: click(3)
        """
        let result = AgentResponseParser.parseResponse(response)
        #expect(result != nil)
        #expect(result?.thought.contains("analyze the page") == true)
        #expect(result?.action == .click(elementId: 3))
    }

    @Test("Returns nil for unparseable response")
    func unparseableResponse() {
        let result = AgentResponseParser.parseResponse("random text with no format")
        #expect(result == nil)
    }

    // MARK: - parseAction: click

    @Test("Parses click with element ID")
    func clickBasic() {
        let action = AgentResponseParser.parseAction("click(5)")
        #expect(action == .click(elementId: 5))
    }

    @Test("Parses click with shift modifier")
    func clickWithShift() {
        let action = AgentResponseParser.parseAction("click(5, shift)")
        #expect(action == .click(elementId: 5, modifiers: ClickModifiers(shift: true)))
    }

    @Test("Parses click with command modifier")
    func clickWithCommand() {
        let action = AgentResponseParser.parseAction("click(10, command)")
        #expect(action == .click(elementId: 10, modifiers: ClickModifiers(command: true)))
    }

    @Test("Parses click with whitespace variations")
    func clickWhitespace() {
        let action = AgentResponseParser.parseAction("click( 5 )")
        #expect(action == .click(elementId: 5))
    }

    // MARK: - parseAction: type

    @Test("Parses type with double-quoted text")
    func typeDoubleQuoted() {
        let action = AgentResponseParser.parseAction(#"type(3, "hello world")"#)
        #expect(action == .type(elementId: 3, text: "hello world"))
    }

    @Test("Parses type with single-quoted text")
    func typeSingleQuoted() {
        let action = AgentResponseParser.parseAction("type(3, 'hello world')")
        #expect(action == .type(elementId: 3, text: "hello world"))
    }

    // MARK: - parseAction: press_enter

    @Test("Parses press_enter")
    func pressEnter() {
        let action = AgentResponseParser.parseAction("press_enter")
        #expect(action == .pressEnter)
    }

    @Test("Parses press_enter case insensitive")
    func pressEnterCaseInsensitive() {
        let action = AgentResponseParser.parseAction("PRESS_ENTER")
        #expect(action == .pressEnter)
    }

    // MARK: - parseAction: scroll

    @Test("Parses scroll down")
    func scrollDown() {
        let action = AgentResponseParser.parseAction("scroll(down)")
        #expect(action == .scroll(direction: .down))
    }

    @Test("Parses scroll up")
    func scrollUp() {
        let action = AgentResponseParser.parseAction("scroll(up)")
        #expect(action == .scroll(direction: .up))
    }

    @Test("Parses scroll top")
    func scrollTop() {
        let action = AgentResponseParser.parseAction("scroll(top)")
        #expect(action == .scroll(direction: .top))
    }

    @Test("Parses scroll bottom")
    func scrollBottom() {
        let action = AgentResponseParser.parseAction("scroll(bottom)")
        #expect(action == .scroll(direction: .bottom))
    }

    // MARK: - parseAction: navigate

    @Test("Parses navigate with URL")
    func navigateURL() {
        let action = AgentResponseParser.parseAction(#"navigate("https://example.com")"#)
        #expect(action == .navigate(url: "https://example.com"))
    }

    @Test("Parses navigate with single-quoted URL")
    func navigateSingleQuoted() {
        let action = AgentResponseParser.parseAction("navigate('https://example.com')")
        #expect(action == .navigate(url: "https://example.com"))
    }

    // MARK: - parseAction: read_text

    @Test("Parses read_text")
    func readText() {
        let action = AgentResponseParser.parseAction("read_text(7)")
        #expect(action == .readText(elementId: 7))
    }

    // MARK: - parseAction: back

    @Test("Parses back()")
    func backWithParens() {
        let action = AgentResponseParser.parseAction("back()")
        #expect(action == .back)
    }

    @Test("Parses back without parens")
    func backWithoutParens() {
        let action = AgentResponseParser.parseAction("back")
        #expect(action == .back)
    }

    // MARK: - parseAction: wait_for_user

    @Test("Parses wait_for_user")
    func waitForUser() {
        let action = AgentResponseParser.parseAction(#"wait_for_user("Need login credentials")"#)
        #expect(action == .waitForUser(reason: "Need login credentials"))
    }

    // MARK: - parseAction: wait

    @Test("Parses wait with integer seconds")
    func waitInteger() {
        let action = AgentResponseParser.parseAction("wait(3)")
        #expect(action == .wait(seconds: 3.0))
    }

    @Test("Parses wait with decimal seconds")
    func waitDecimal() {
        let action = AgentResponseParser.parseAction("wait(1.5)")
        #expect(action == .wait(seconds: 1.5))
    }

    // MARK: - parseAction: done

    @Test("Parses done with summary")
    func doneWithSummary() {
        let action = AgentResponseParser.parseAction(#"done("Task completed successfully")"#)
        #expect(action == .done(summary: "Task completed successfully"))
    }

    // MARK: - parseAction: multi-action truncation

    @Test("Multi-action response truncated to first action")
    func multiActionTruncated() {
        let action = AgentResponseParser.parseAction("""
        click(5)
        THOUGHT: Now I should type
        ACTION: type(3, "hello")
        """)
        #expect(action == .click(elementId: 5))
    }

    // MARK: - parseAction: edge cases

    @Test("Returns nil for empty string")
    func emptyAction() {
        let action = AgentResponseParser.parseAction("")
        #expect(action == nil)
    }

    @Test("Returns nil for garbage input")
    func garbageAction() {
        let action = AgentResponseParser.parseAction("asdfghjkl")
        #expect(action == nil)
    }

    @Test("Handles leading/trailing whitespace")
    func whitespaceHandling() {
        let action = AgentResponseParser.parseAction("  click(5)  ")
        #expect(action == .click(elementId: 5))
    }

    // MARK: - parseAction: scrape

    @Test("Parses scrape with double-quoted URL")
    func scrapeDoubleQuoted() {
        let action = AgentResponseParser.parseAction(#"scrape("https://example.com", 2, 100)"#)
        #expect(action == .scrape(url: "https://example.com", depth: 2, maxPages: 100))
    }

    @Test("Parses scrape with single-quoted URL")
    func scrapeSingleQuoted() {
        let action = AgentResponseParser.parseAction("scrape('https://example.com/path', 1, 50)")
        #expect(action == .scrape(url: "https://example.com/path", depth: 1, maxPages: 50))
    }

    @Test("Parses scrape with whitespace variations")
    func scrapeWhitespace() {
        let action = AgentResponseParser.parseAction(#"scrape( "https://example.com" , 3 , 200 )"#)
        #expect(action == .scrape(url: "https://example.com", depth: 3, maxPages: 200))
    }

    // MARK: - parseAction: new_tab

    @Test("Parses new_tab")
    func newTab() {
        let action = AgentResponseParser.parseAction("new_tab")
        #expect(action == .newTab)
    }

    @Test("Parses new_tab case insensitive")
    func newTabCaseInsensitive() {
        let action = AgentResponseParser.parseAction("NEW_TAB")
        #expect(action == .newTab)
    }

    // MARK: - parseAction: open_tab

    @Test("Parses open_tab with double-quoted URL")
    func openTabDoubleQuoted() {
        let action = AgentResponseParser.parseAction(#"open_tab("https://example.com")"#)
        #expect(action == .openTab(url: "https://example.com"))
    }

    @Test("Parses open_tab with single-quoted URL")
    func openTabSingleQuoted() {
        let action = AgentResponseParser.parseAction("open_tab('https://example.com/page')")
        #expect(action == .openTab(url: "https://example.com/page"))
    }

    // MARK: - parseAction: switch_tab

    @Test("Parses switch_tab with index")
    func switchTab() {
        let action = AgentResponseParser.parseAction("switch_tab(2)")
        #expect(action == .switchTab(index: 2))
    }

    @Test("Parses switch_tab with whitespace")
    func switchTabWhitespace() {
        let action = AgentResponseParser.parseAction("switch_tab( 3 )")
        #expect(action == .switchTab(index: 3))
    }

    // MARK: - parseAction: extract_content

    @Test("Parses extract_content")
    func extractContent() {
        let action = AgentResponseParser.parseAction("extract_content")
        #expect(action == .extractContent)
    }

    @Test("Parses extract_content case insensitive")
    func extractContentCaseInsensitive() {
        let action = AgentResponseParser.parseAction("EXTRACT_CONTENT")
        #expect(action == .extractContent)
    }

    // MARK: - parseAction: read_links

    @Test("Parses read_links")
    func readLinks() {
        let action = AgentResponseParser.parseAction("read_links")
        #expect(action == .readLinks)
    }

    @Test("Parses read_links case insensitive")
    func readLinksCaseInsensitive() {
        let action = AgentResponseParser.parseAction("READ_LINKS")
        #expect(action == .readLinks)
    }
}
