import Foundation
import FoundationModels

@Generable(description: "The next browser action decision.")
struct GeneratedAgentDecision: Sendable {
    @Guide(description: "Brief reasoning about the next step.")
    let thought: String

    let action: GeneratedAgentAction

    init(thought: String, action: GeneratedAgentAction) {
        self.thought = thought
        self.action = action
    }

    func toDecision() throws -> (thought: String, action: AgentAction) {
        let normalizedThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThought.isEmpty else {
            throw AgentError.invalidLLMResponse("Structured agent decision omitted thought")
        }

        return (normalizedThought, try action.toAgentAction())
    }
}

@Generable(description: "A single browser action with typed parameters.")
struct GeneratedAgentAction: Sendable {
    @Guide(description: "One of: click, type, press_enter, scroll, navigate, back, wait_for_user, wait, read_text, new_tab, open_tab, switch_tab, extract_content, read_links, done")
    let actionType: String

    @Guide(description: "Element ID for click, type, or read_text actions.")
    let elementId: Int?

    @Guide(description: "Text to type for the type action.")
    let text: String?

    @Guide(description: "URL for navigate or open_tab actions.")
    let url: String?

    @Guide(description: "One of: up, down, top, bottom for scroll actions.")
    let scrollDirection: String?

    @Guide(description: "Modifier keys for click actions. Valid values: shift, command, control, option.")
    let modifiers: [String]?

    @Guide(description: "1-based tab index for switch_tab actions.")
    let tabIndex: Int?

    @Guide(description: "Reason shown to the user for wait_for_user actions.")
    let reason: String?

    @Guide(description: "Number of seconds for wait actions.")
    let waitSeconds: Double?

    @Guide(description: "Completion summary for done actions.")
    let summary: String?

    init(
        actionType: String,
        elementId: Int?,
        text: String?,
        url: String?,
        scrollDirection: String?,
        modifiers: [String]?,
        tabIndex: Int?,
        reason: String?,
        waitSeconds: Double?,
        summary: String?
    ) {
        self.actionType = actionType
        self.elementId = elementId
        self.text = text
        self.url = url
        self.scrollDirection = scrollDirection
        self.modifiers = modifiers
        self.tabIndex = tabIndex
        self.reason = reason
        self.waitSeconds = waitSeconds
        self.summary = summary
    }

    func toAgentAction() throws -> AgentAction {
        switch actionType.lowercased() {
        case "click":
            guard let elementId else {
                throw AgentError.invalidLLMResponse("Structured click action omitted elementId")
            }
            return .click(elementId: elementId, modifiers: ClickModifiers.from(modifiers ?? []))

        case "type":
            guard let elementId else {
                throw AgentError.invalidLLMResponse("Structured type action omitted elementId")
            }
            guard let text, !text.isEmpty else {
                throw AgentError.invalidLLMResponse("Structured type action omitted text")
            }
            return .type(elementId: elementId, text: text)

        case "press_enter":
            return .pressEnter

        case "scroll":
            guard let scrollDirection,
                  let direction = AgentAction.ScrollDirection(rawValue: scrollDirection.lowercased()) else {
                throw AgentError.invalidLLMResponse("Structured scroll action omitted a valid direction")
            }
            return .scroll(direction: direction)

        case "navigate":
            guard let url, !url.isEmpty else {
                throw AgentError.invalidLLMResponse("Structured navigate action omitted url")
            }
            return .navigate(url: url)

        case "back":
            return .back

        case "wait_for_user":
            return .waitForUser(reason: reason ?? "User action required")

        case "wait":
            guard let waitSeconds else {
                throw AgentError.invalidLLMResponse("Structured wait action omitted waitSeconds")
            }
            return .wait(seconds: waitSeconds)

        case "read_text":
            guard let elementId else {
                throw AgentError.invalidLLMResponse("Structured read_text action omitted elementId")
            }
            return .readText(elementId: elementId)

        case "new_tab":
            return .newTab

        case "open_tab":
            guard let url, !url.isEmpty else {
                throw AgentError.invalidLLMResponse("Structured open_tab action omitted url")
            }
            return .openTab(url: url)

        case "switch_tab":
            guard let tabIndex else {
                throw AgentError.invalidLLMResponse("Structured switch_tab action omitted tabIndex")
            }
            return .switchTab(index: tabIndex)

        case "extract_content":
            return .extractContent

        case "read_links":
            return .readLinks

        case "done":
            return .done(summary: summary ?? "Task completed")

        default:
            throw AgentError.invalidLLMResponse("Unknown structured action type: \(actionType)")
        }
    }

    init(from action: AgentAction) {
        switch action {
        case .click(let elementId, let modifiers):
            self.init(
                actionType: "click",
                elementId: elementId,
                text: nil,
                url: nil,
                scrollDirection: nil,
                modifiers: {
                    var values: [String] = []
                    if modifiers.shift { values.append("shift") }
                    if modifiers.command { values.append("command") }
                    if modifiers.control { values.append("control") }
                    if modifiers.option { values.append("option") }
                    return values.isEmpty ? nil : values
                }(),
                tabIndex: nil,
                reason: nil,
                waitSeconds: nil,
                summary: nil
            )
        case .type(let elementId, let text):
            self.init(actionType: "type", elementId: elementId, text: text, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .pressEnter:
            self.init(actionType: "press_enter", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .scroll(let direction):
            self.init(actionType: "scroll", elementId: nil, text: nil, url: nil, scrollDirection: direction.rawValue, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .navigate(let url):
            self.init(actionType: "navigate", elementId: nil, text: nil, url: url, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .back:
            self.init(actionType: "back", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .waitForUser(let reason):
            self.init(actionType: "wait_for_user", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: reason, waitSeconds: nil, summary: nil)
        case .wait(let seconds):
            self.init(actionType: "wait", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: seconds, summary: nil)
        case .readText(let elementId):
            self.init(actionType: "read_text", elementId: elementId, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .newTab:
            self.init(actionType: "new_tab", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .openTab(let url):
            self.init(actionType: "open_tab", elementId: nil, text: nil, url: url, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .switchTab(let index):
            self.init(actionType: "switch_tab", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: index, reason: nil, waitSeconds: nil, summary: nil)
        case .extractContent:
            self.init(actionType: "extract_content", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .readLinks:
            self.init(actionType: "read_links", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .done(let summary):
            self.init(actionType: "done", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: summary)
        }
    }
}
