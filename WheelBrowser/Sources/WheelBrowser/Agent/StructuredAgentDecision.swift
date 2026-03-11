import Foundation

struct GeneratedAgentDecision: Codable, Sendable, WheelStructuredSpecProviding {
    let thought: String

    let action: GeneratedAgentAction

    init(thought: String, action: GeneratedAgentAction) {
        self.thought = thought
        self.action = action
    }

    var transcriptSummary: String {
        action.transcriptSummary
    }

    func toDecision() throws -> (thought: String, action: AgentAction) {
        let normalizedThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThought.isEmpty else {
            throw AgentError.invalidLLMResponse("Structured agent decision omitted thought")
        }

        return (normalizedThought, try action.toAgentAction())
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedAgentDecision",
        description: "The next browser action decision.",
        properties: [
            WheelOutputSchema.property(
                "thought",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Brief reasoning about the next step."
            ),
            WheelOutputSchema.property(
                "action",
                schema: GeneratedAgentAction.outputSchema,
                description: "A single browser action with typed parameters."
            ),
        ]
    )

    static let spec = structuredSpec { $0.transcriptSummary }
}

struct GeneratedAgentAction: Codable, Sendable {
    let actionType: String

    let elementId: Int?

    let text: String?

    let url: String?

    let scrollDirection: String?

    let modifiers: [String]?

    let tabIndex: Int?

    let reason: String?

    let waitSeconds: Double?

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

        case "collect_links":
            return .collectLinks

        case "advance_pagination":
            return .advancePagination(url: url)

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
        case .collectLinks:
            self.init(actionType: "collect_links", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .advancePagination(let url):
            self.init(actionType: "advance_pagination", elementId: nil, text: nil, url: url, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: nil)
        case .done(let summary):
            self.init(actionType: "done", elementId: nil, text: nil, url: nil, scrollDirection: nil, modifiers: nil, tabIndex: nil, reason: nil, waitSeconds: nil, summary: summary)
        }
    }

    var transcriptSummary: String {
        switch actionType.lowercased() {
        case "click":
            return elementId.map { "Action: click #\($0)" } ?? "Action: click"
        case "type":
            return elementId.map { "Action: type into #\($0)" } ?? "Action: type"
        case "press_enter":
            return "Action: press_enter"
        case "scroll":
            return "Action: scroll \(scrollDirection ?? "down")"
        case "navigate":
            return "Action: navigate \(url ?? "")".trimmingCharacters(in: .whitespaces)
        case "back":
            return "Action: back"
        case "wait_for_user":
            return "Action: wait_for_user"
        case "wait":
            return "Action: wait \(waitSeconds ?? 0)"
        case "read_text":
            return elementId.map { "Action: read_text #\($0)" } ?? "Action: read_text"
        case "new_tab":
            return "Action: new_tab"
        case "open_tab":
            return "Action: open_tab \(url ?? "")".trimmingCharacters(in: .whitespaces)
        case "switch_tab":
            return tabIndex.map { "Action: switch_tab #\($0)" } ?? "Action: switch_tab"
        case "extract_content":
            return "Action: extract_content"
        case "read_links":
            return "Action: read_links"
        case "collect_links":
            return "Action: collect_links"
        case "advance_pagination":
            return "Action: advance_pagination"
        case "done":
            return "Action: done \(summary ?? "Task completed")"
        default:
            return "Action: \(actionType)"
        }
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedAgentAction",
        description: "A single browser action with typed parameters.",
        properties: [
            WheelOutputSchema.property(
                "actionType",
                schema: WheelOutputSchema.enumeration(
                    name: "ActionType",
                    cases: [
                        "click",
                        "type",
                        "press_enter",
                        "scroll",
                        "navigate",
                        "back",
                        "wait_for_user",
                        "wait",
                        "read_text",
                        "new_tab",
                        "open_tab",
                        "switch_tab",
                        "extract_content",
                        "read_links",
                        "collect_links",
                        "advance_pagination",
                        "done",
                    ]
                ),
                description: "The action type."
            ),
            WheelOutputSchema.property(
                "elementId",
                schema: WheelOutputSchema.integer(minimum: 0),
                description: "Element ID for click, type, or read_text actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "text",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Text to type for the type action.",
                optional: true
            ),
            WheelOutputSchema.property(
                "url",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "URL for navigate, open_tab, or advance_pagination actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "scrollDirection",
                schema: WheelOutputSchema.enumeration(
                    name: "ScrollDirection",
                    cases: ["up", "down", "top", "bottom"]
                ),
                description: "Scroll direction for scroll actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "modifiers",
                schema: WheelOutputSchema.array(
                    item: WheelOutputSchema.enumeration(
                        name: "ModifierKey",
                        cases: ["shift", "command", "control", "option"]
                    )
                ),
                description: "Modifier keys for click actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "tabIndex",
                schema: WheelOutputSchema.integer(minimum: 1),
                description: "1-based tab index for switch_tab actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "reason",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Reason shown to the user for wait_for_user actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "waitSeconds",
                schema: WheelOutputSchema.number(minimum: 0),
                description: "Number of seconds for wait actions.",
                optional: true
            ),
            WheelOutputSchema.property(
                "summary",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Completion summary for done actions.",
                optional: true
            ),
        ]
    )
}
