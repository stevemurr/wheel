import Testing
@testable import WheelBrowser

@Suite("StructuredAgentDecision Tests")
struct StructuredAgentDecisionTests {
    @Test("Generated click action round-trips to AgentAction")
    func clickActionRoundTrip() throws {
        let action = GeneratedAgentAction(
            actionType: "click",
            elementId: 5,
            text: nil,
            url: nil,
            scrollDirection: nil,
            modifiers: ["shift", "command"],
            tabIndex: nil,
            reason: nil,
            waitSeconds: nil,
            summary: nil
        )

        #expect(try action.toAgentAction() == .click(
            elementId: 5,
            modifiers: ClickModifiers(shift: true, command: true)
        ))
    }

    @Test("Generated done action uses default summary when omitted")
    func doneActionDefaultSummary() throws {
        let action = GeneratedAgentAction(
            actionType: "done",
            elementId: nil,
            text: nil,
            url: nil,
            scrollDirection: nil,
            modifiers: nil,
            tabIndex: nil,
            reason: nil,
            waitSeconds: nil,
            summary: nil
        )

        #expect(try action.toAgentAction() == .done(summary: "Task completed"))
    }

    @Test("Generated type action requires text")
    func typeActionRequiresText() {
        let action = GeneratedAgentAction(
            actionType: "type",
            elementId: 3,
            text: nil,
            url: nil,
            scrollDirection: nil,
            modifiers: nil,
            tabIndex: nil,
            reason: nil,
            waitSeconds: nil,
            summary: nil
        )

        #expect(throws: AgentError.self) {
            _ = try action.toAgentAction()
        }
    }

    @Test("Structured agent decision trims thought and converts action")
    func decisionConversion() throws {
        let decision = GeneratedAgentDecision(
            thought: "  Click the first result  ",
            action: GeneratedAgentAction(
                actionType: "open_tab",
                elementId: nil,
                text: nil,
                url: "https://example.com",
                scrollDirection: nil,
                modifiers: nil,
                tabIndex: nil,
                reason: nil,
                waitSeconds: nil,
                summary: nil
            )
        )

        let converted = try decision.toDecision()
        #expect(converted.thought == "Click the first result")
        #expect(converted.action == .openTab(url: "https://example.com"))
    }

    @Test("GeneratedAgentAction can be created from AgentAction")
    func actionInitFromAgentAction() throws {
        let generated = GeneratedAgentAction(from: .switchTab(index: 2))

        #expect(generated.actionType == "switch_tab")
        #expect(generated.tabIndex == 2)
        #expect(try generated.toAgentAction() == .switchTab(index: 2))
    }

    @Test("Generated advance pagination action round-trips to AgentAction")
    func advancePaginationRoundTrip() throws {
        let action = GeneratedAgentAction(
            actionType: "advance_pagination",
            elementId: nil,
            text: nil,
            url: "https://news.ycombinator.com/news?p=2",
            scrollDirection: nil,
            modifiers: nil,
            tabIndex: nil,
            reason: nil,
            waitSeconds: nil,
            summary: nil
        )

        #expect(try action.toAgentAction() == .advancePagination(url: "https://news.ycombinator.com/news?p=2"))
        #expect(GeneratedAgentAction(from: .advancePagination(url: nil)).actionType == "advance_pagination")
    }
}
