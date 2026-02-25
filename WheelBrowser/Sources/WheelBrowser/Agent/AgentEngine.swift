import Foundation
import SwiftUI
import Combine
import os.log

private let agentLog = Logger(subsystem: "com.wheel.browser", category: "AgentEngine")

/// Represents a single step in the agent's execution
struct AgentStep: Identifiable {
    let id = UUID()
    let type: StepType
    let content: String
    let timestamp: Date

    enum StepType {
        case observation  // Page state observed
        case thought      // LLM reasoning
        case action       // Action taken
        case result       // Action result
        case error        // Error occurred
        case done         // Task completed
    }
}

/// The result of an agent task
struct AgentResult {
    let success: Bool
    let summary: String
    let steps: [AgentStep]
}

/// Available actions the agent can take
enum AgentAction: Equatable {
    case click(elementId: Int)
    case type(elementId: Int, text: String)
    case pressEnter
    case scroll(direction: ScrollDirection)
    case navigate(url: String)
    case back
    case waitForUser(reason: String)
    case wait(seconds: Double)
    case done(summary: String)

    enum ScrollDirection: String {
        case up, down, top, bottom
    }
}

/// Represents a normalized action for loop detection (ignores element ID specifics)
private struct NormalizedAction: Hashable {
    let type: String  // "click", "type", "scroll", etc.
    let target: String  // Normalized target info (element text/role, not ID)

    init(from action: AgentAction, elementDescription: String? = nil) {
        switch action {
        case .click:
            self.type = "click"
            self.target = elementDescription ?? "unknown"
        case .type(_, let text):
            self.type = "type"
            self.target = text  // What text is being typed
        case .pressEnter:
            self.type = "pressEnter"
            self.target = ""
        case .scroll(let direction):
            self.type = "scroll"
            self.target = direction.rawValue
        case .navigate(let url):
            self.type = "navigate"
            self.target = url
        case .back:
            self.type = "back"
            self.target = ""
        case .waitForUser(let reason):
            self.type = "waitForUser"
            self.target = reason
        case .wait:
            self.type = "wait"
            self.target = ""
        case .done:
            self.type = "done"
            self.target = ""
        }
    }
}

/// The ReAct agent engine for browser automation
@MainActor
class AgentEngine: ObservableObject {
    // MARK: - Published State

    @Published var isRunning: Bool = false
    @Published var currentTask: String = ""
    @Published var steps: [AgentStep] = []
    @Published var progress: String = ""
    @Published var error: String?
    @Published var boundTabId: UUID?

    // MARK: - Dependencies

    private let browserState: BrowserState
    private let settings: AppSettings
    private var currentTaskHandle: Task<AgentResult, Never>?
    private weak var boundTab: Tab?
    private var tabClosureObserver: AnyCancellable?

    // MARK: - Loop Detection State

    /// History of recent actions for semantic loop detection
    private var recentNormalizedActions: [NormalizedAction] = []
    /// Track consecutive parse failures for backoff
    private var consecutiveParseFailures: Int = 0
    private let maxConsecutiveParseFailures = 3
    /// Track loop recovery attempts (how many times we've tried backing out)
    private var loopRecoveryAttempts: Int = 0
    private let maxLoopRecoveryAttempts = 2
    /// Whether we're waiting for user to solve a captcha
    @Published var isWaitingForUser: Bool = false
    @Published var waitingReason: String = ""

    // MARK: - Configuration

    private let maxIterations = 20
    private let systemPrompt = """
    You are a browser automation agent. Analyze the page snapshot and decide what action to take.

    RESPONSE FORMAT (you must follow this exactly):
    THOUGHT: [your reasoning]
    ACTION: [one action]

    AVAILABLE ACTIONS:
    click(id)          - Click element by ID
    type(id, "text")   - Type text into element
    press_enter        - Press enter key
    scroll(up/down)    - Scroll the page
    navigate("url")    - Go to URL
    back()             - Go back to the previous page (use when stuck or need to try a different path)
    done("summary")    - IMPORTANT: Call this when the task is complete!

    WHEN TO CALL done():
    - The requested information is visible on the page
    - The requested action has been performed
    - You have navigated to the target page
    - The search results are showing
    - There is nothing more to do

    WHEN TO CALL back():
    - You're stuck on a page that doesn't help with the task
    - The current approach isn't working and you want to try a different path
    - You accidentally navigated to the wrong page

    CAPTCHA/CHALLENGE PAGES:
    - If you see a captcha, challenge, or "verify you are human" page, call wait_for_user("reason")
    - The user will solve the captcha and the page will update automatically

    CORRECT EXAMPLES:
    THOUGHT: I need to click the search button.
    ACTION: click(5)

    THOUGHT: The search results are now showing. Task complete.
    ACTION: done("Successfully searched and found results")

    THOUGHT: This page isn't what I need, let me go back and try a different link.
    ACTION: back()

    RULES:
    - Call done() as soon as the task objective is achieved
    - Do NOT keep taking actions after the task is complete
    - If stuck in a loop, try back() to take a different approach
    - Output ONLY plain text with THOUGHT: and ACTION: labels
    - Do NOT use JSON, XML, special tokens, or <|tags|>
    """

    // MARK: - Initialization

    init(browserState: BrowserState, settings: AppSettings) {
        self.browserState = browserState
        self.settings = settings
    }

    /// Returns the title of the bound tab, if any
    var boundTabTitle: String? {
        boundTab?.title
    }

    /// Returns whether the agent is running on a background tab (not the active tab)
    var isRunningInBackground: Bool {
        guard let boundId = boundTabId else { return false }
        return browserState.activeTabId != boundId
    }

    // MARK: - Public API

    /// Run an agent task
    func run(task: String) async -> AgentResult {
        guard !isRunning else {
            return AgentResult(success: false, summary: "Agent is already running", steps: [])
        }

        // Bind to the current active tab
        guard let activeTab = browserState.activeTab else {
            return AgentResult(success: false, summary: "No active tab", steps: [])
        }

        boundTabId = activeTab.id
        boundTab = activeTab
        activeTab.hasActiveAgent = true
        activeTab.agentProgress = "Starting..."

        // Set up observer for tab closure
        setupTabClosureObserver()

        // Reset state
        isRunning = true
        currentTask = task
        steps = []
        error = nil
        progress = "Starting..."

        let taskHandle = Task { () -> AgentResult in
            do {
                let result = try await executeTask(task)
                return result
            } catch {
                agentLog.error("[Agent] Task failed with error: \(error.localizedDescription)")
                print("[Agent] ❌ Task failed with error: \(error.localizedDescription)")
                let errorStep = AgentStep(type: .error, content: error.localizedDescription, timestamp: Date())
                await MainActor.run {
                    self.steps.append(errorStep)
                    self.error = error.localizedDescription
                }
                return AgentResult(success: false, summary: error.localizedDescription, steps: self.steps)
            }
        }

        currentTaskHandle = taskHandle

        let result = await taskHandle.value
        cleanupTabBinding()
        isRunning = false
        return result
    }

    /// Set up observer to detect when the bound tab is closed
    private func setupTabClosureObserver() {
        tabClosureObserver?.cancel()
        tabClosureObserver = browserState.$tabs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tabs in
                guard let self = self,
                      let boundId = self.boundTabId,
                      self.isRunning else { return }

                // Check if bound tab still exists
                if !tabs.contains(where: { $0.id == boundId }) {
                    agentLog.warning("[Agent] Bound tab was closed, cancelling agent")
                    print("[Agent] ⚠️ Bound tab was closed, cancelling agent")
                    self.error = "Tab was closed"
                    let errorStep = AgentStep(type: .error, content: "Task cancelled: tab was closed", timestamp: Date())
                    self.steps.append(errorStep)
                    self.cancel()
                }
            }
    }

    /// Clean up tab binding when agent finishes
    private func cleanupTabBinding() {
        tabClosureObserver?.cancel()
        tabClosureObserver = nil

        if let tab = boundTab {
            tab.hasActiveAgent = false
            tab.agentProgress = ""
        }

        boundTab = nil
        boundTabId = nil
    }

    /// Cancel the current task
    func cancel() {
        currentTaskHandle?.cancel()
        currentTaskHandle = nil
        cleanupTabBinding()
        isRunning = false
        progress = "Cancelled"
    }

    // MARK: - Private Methods

    private func executeTask(_ task: String) async throws -> AgentResult {
        var iteration = 0
        agentLog.info("[Agent] Starting task: \(task)")
        print("[Agent] 🚀 Starting task: \(task)")

        // Reset loop detection state
        recentNormalizedActions = []
        consecutiveParseFailures = 0
        loopRecoveryAttempts = 0
        isWaitingForUser = false
        waitingReason = ""

        // Ensure we have a bound tab
        guard let tabId = boundTabId else {
            throw AgentError.webViewUnavailable
        }

        while iteration < maxIterations {
            try Task.checkCancellation()

            iteration += 1
            let progressText = "Step \(iteration)/\(maxIterations)"
            progress = progressText

            // Update bound tab progress
            if let tab = boundTab {
                tab.agentProgress = progressText
            }

            // 1. Observe - Get page snapshot (use bound tab, not active tab)
            guard let bridge = browserState.accessibilityBridge(for: tabId) else {
                throw AgentError.webViewUnavailable
            }

            let snapshot = try await bridge.snapshot()
            let observationStep = AgentStep(
                type: .observation,
                content: "Page: \(snapshot.title)\nURL: \(snapshot.url)\n\(snapshot.elements.count) interactive elements",
                timestamp: Date()
            )
            steps.append(observationStep)

            // 2. Think - Ask LLM for next action
            let prompt = buildPrompt(task: task, snapshot: snapshot, previousSteps: steps)
            agentLog.debug("[Agent] Sending prompt to LLM (length: \(prompt.count) chars)")
            let llmResponse = try await callLLM(prompt: prompt)
            agentLog.info("[Agent] LLM Response:\n\(llmResponse)")
            print("[Agent] LLM Response:\n\(llmResponse)")

            // Parse thought and action
            guard let (thought, action) = parseResponse(llmResponse) else {
                self.consecutiveParseFailures += 1
                let failureCount = self.consecutiveParseFailures
                let maxFailures = self.maxConsecutiveParseFailures
                agentLog.warning("[Agent] Parse failed (attempt \(failureCount)/\(maxFailures)). Raw response:\n\(llmResponse)")
                print("[Agent] ⚠️ PARSE FAILED (attempt \(failureCount)/\(maxFailures)) - Raw response:\n\(llmResponse)")

                // Check if we've exceeded max consecutive parse failures
                if failureCount >= maxFailures {
                    agentLog.error("[Agent] Max consecutive parse failures reached, aborting")
                    print("[Agent] ❌ Max consecutive parse failures (\(maxFailures)) reached")
                    let errorStep = AgentStep(type: .error, content: "Failed to parse LLM response after \(maxFailures) attempts", timestamp: Date())
                    steps.append(errorStep)
                    throw AgentError.invalidLLMResponse("Unable to parse response after \(maxFailures) attempts")
                }

                // Exponential backoff: 1s, 2s, 4s
                let backoffSeconds = pow(2.0, Double(failureCount - 1))
                agentLog.info("[Agent] Backing off for \(backoffSeconds)s before retry")
                print("[Agent] Backing off for \(backoffSeconds)s before retry")
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))

                let errorStep = AgentStep(type: .error, content: "Failed to parse LLM response (retrying after \(Int(backoffSeconds))s backoff...)", timestamp: Date())
                steps.append(errorStep)
                continue
            }

            // Reset parse failure counter on successful parse
            self.consecutiveParseFailures = 0
            agentLog.info("[Agent] Parsed - Thought: \(thought), Action: \(String(describing: action))")
            print("[Agent] Parsed - Thought: \(thought)")

            let thoughtStep = AgentStep(type: .thought, content: thought, timestamp: Date())
            steps.append(thoughtStep)

            let actionDescription = describeAction(action)
            let actionStep = AgentStep(type: .action, content: actionDescription, timestamp: Date())
            steps.append(actionStep)

            // Build normalized action for loop detection
            // For click actions, get the element description from the snapshot to compare semantically
            var elementDescription: String? = nil
            if case .click(let elementId) = action {
                if let element = snapshot.elements.first(where: { $0.id == elementId }) {
                    // Use element's semantic identifiers, not its numeric ID
                    elementDescription = "\(element.tag):\(element.text ?? element.ariaLabel ?? element.placeholder ?? "unknown")"
                }
            }
            let normalizedAction = NormalizedAction(from: action, elementDescription: elementDescription)
            recentNormalizedActions.append(normalizedAction)

            // Keep only last 8 actions for pattern detection
            if recentNormalizedActions.count > 8 {
                recentNormalizedActions.removeFirst()
            }

            // Enhanced loop detection: check for various stuck patterns
            if let loopType = detectStuckLoop() {
                agentLog.warning("[Agent] Detected stuck loop: \(loopType)")

                // Try to recover by backing out if we haven't exhausted recovery attempts
                if loopRecoveryAttempts < maxLoopRecoveryAttempts {
                    loopRecoveryAttempts += 1
                    print("[Agent] ⚠️ Stuck loop detected (\(loopType)) - attempting recovery \(loopRecoveryAttempts)/\(maxLoopRecoveryAttempts)")

                    // Check if we can go back
                    if let tab = boundTab, tab.canGoBack {
                        let recoveryStep = AgentStep(type: .action, content: "Loop detected, going back to try different approach", timestamp: Date())
                        steps.append(recoveryStep)

                        // Go back
                        tab.goBack()
                        try await bridge.waitForLoad(timeout: 5.0)

                        // Clear recent actions to give fresh start
                        recentNormalizedActions = []

                        let resultStep = AgentStep(type: .result, content: "Navigated back after loop detection", timestamp: Date())
                        steps.append(resultStep)

                        // Continue to next iteration with fresh state
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                }

                // Exhausted recovery attempts or can't go back
                print("[Agent] ⚠️ Stuck loop detected (\(loopType)) - forcing completion")
                let doneStep = AgentStep(type: .done, content: "Task ended: \(loopType)", timestamp: Date())
                steps.append(doneStep)
                return AgentResult(success: false, summary: "Agent got stuck: \(loopType)", steps: steps)
            }

            // 3. Act - Execute the action
            do {
                let result = try await executeAction(action, bridge: bridge)

                if case .done(let summary) = action {
                    agentLog.info("[Agent] Task completed successfully: \(summary)")
                    print("[Agent] ✅ Task completed successfully: \(summary)")
                    let doneStep = AgentStep(type: .done, content: summary, timestamp: Date())
                    steps.append(doneStep)
                    return AgentResult(success: true, summary: summary, steps: steps)
                }

                let resultStep = AgentStep(type: .result, content: result, timestamp: Date())
                steps.append(resultStep)

                // Small delay between actions
                try await Task.sleep(nanoseconds: 500_000_000)

            } catch {
                let errorStep = AgentStep(type: .error, content: error.localizedDescription, timestamp: Date())
                steps.append(errorStep)
            }
        }

        agentLog.error("[Agent] Max iterations (\(self.maxIterations)) reached without completion")
        print("[Agent] ❌ Max iterations (\(self.maxIterations)) reached without completion")
        throw AgentError.maxIterationsReached
    }

    private func buildPrompt(task: String, snapshot: PageSnapshot, previousSteps: [AgentStep]) -> String {
        var prompt = "TASK: \(task)\n\n"
        prompt += "CURRENT PAGE STATE:\n"
        prompt += snapshot.textRepresentation
        prompt += "\n\n"

        // Include recent history
        let recentSteps = previousSteps.suffix(6)
        if !recentSteps.isEmpty {
            prompt += "RECENT HISTORY:\n"
            for step in recentSteps {
                let typeLabel: String
                switch step.type {
                case .observation: typeLabel = "OBSERVED"
                case .thought: typeLabel = "THOUGHT"
                case .action: typeLabel = "ACTION"
                case .result: typeLabel = "RESULT"
                case .error: typeLabel = "ERROR"
                case .done: typeLabel = "DONE"
                }
                prompt += "\(typeLabel): \(step.content)\n"
            }
            prompt += "\n"
        }

        // Check for repeated actions (loop detection)
        let recentActions = previousSteps.filter { $0.type == .action }.suffix(3).map { $0.content }
        let isLooping = recentActions.count >= 2 && Set(recentActions).count == 1

        // Count steps to know how far along we are
        let stepCount = previousSteps.filter { $0.type == .action }.count

        if isLooping {
            prompt += "WARNING: You have repeated the same action multiple times. Consider if the task is already complete and call done() if so.\n\n"
        } else if stepCount >= 5 {
            prompt += "REMINDER: If the task objective has been achieved, call done(\"summary\") to complete.\n\n"
        }

        prompt += "What should I do next? If the task is complete, call done().\n"
        return prompt
    }

    /// Detect if the agent is stuck in a loop pattern
    /// Returns a description of the loop type if detected, nil otherwise
    private func detectStuckLoop() -> String? {
        let actions = recentNormalizedActions

        // Need at least 4 actions to detect patterns
        guard actions.count >= 4 else { return nil }

        // Pattern 1: Same action repeated 4+ times in a row
        let lastFour = Array(actions.suffix(4))
        if Set(lastFour).count == 1 {
            return "Same action repeated 4 times"
        }

        // Pattern 2: Oscillating between 2 actions (A-B-A-B pattern)
        if actions.count >= 4 {
            let a1 = actions[actions.count - 4]
            let a2 = actions[actions.count - 3]
            let a3 = actions[actions.count - 2]
            let a4 = actions[actions.count - 1]

            if a1 == a3 && a2 == a4 && a1 != a2 {
                return "Oscillating between two actions"
            }
        }

        // Pattern 3: Same action type on different elements (click-click-click even if different targets)
        if actions.count >= 5 {
            let lastFiveTypes = actions.suffix(5).map { $0.type }
            if Set(lastFiveTypes).count == 1 && lastFiveTypes[0] == "click" {
                // All 5 recent actions are clicks - likely stuck trying different elements
                let lastFiveTargets = Set(actions.suffix(5).map { $0.target })
                if lastFiveTargets.count <= 2 {
                    // Clicking same 1-2 elements repeatedly
                    return "Repeatedly clicking same elements"
                }
            }
        }

        // Pattern 4: Scroll loop (scrolling same direction repeatedly without progress)
        if actions.count >= 6 {
            let lastSix = actions.suffix(6)
            let scrollActions = lastSix.filter { $0.type == "scroll" }
            if scrollActions.count >= 4 {
                let directions = Set(scrollActions.map { $0.target })
                if directions.count == 1 {
                    return "Scroll loop without progress"
                }
            }
        }

        // Pattern 5: Three-action cycle (A-B-C-A-B-C)
        if actions.count >= 6 {
            let a1 = actions[actions.count - 6]
            let a2 = actions[actions.count - 5]
            let a3 = actions[actions.count - 4]
            let a4 = actions[actions.count - 3]
            let a5 = actions[actions.count - 2]
            let a6 = actions[actions.count - 1]

            if a1 == a4 && a2 == a5 && a3 == a6 {
                return "Three-action cycle detected"
            }
        }

        return nil
    }

    /// Try to extract an action from reasoning content that doesn't have THOUGHT/ACTION markers
    /// This handles reasoning models that explain what they'll do without using the required format
    private func extractActionFromReasoning(_ reasoning: String) -> String? {
        // Look for explicit action mentions at the end of reasoning
        // Common patterns: "Let's do X", "So we should X", "Thus: X", "ACTION: X"

        // Pattern: navigate("url") or navigate(url)
        if let match = reasoning.range(of: #"navigate\s*\(\s*[\"']?https?://[^\s\"'\)]+[\"']?\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // Pattern: "Let's navigate to URL" or "navigate to URL"
        if let match = reasoning.range(of: #"(?:let's\s+)?navigate\s+(?:to\s+)?[\"']?(https?://[^\s\"']+)[\"']?"#, options: [.regularExpression, .caseInsensitive]) {
            let segment = String(reasoning[match])
            // Extract URL from the match
            if let urlMatch = segment.range(of: #"https?://[^\s\"']+"#, options: .regularExpression) {
                let url = String(segment[urlMatch])
                return "navigate(\"\(url)\")"
            }
        }

        // Pattern: type(id, "text")
        if let match = reasoning.range(of: #"type\s*\(\s*\d+\s*,\s*[\"'][^\"']+[\"']\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // Pattern: click(id)
        if let match = reasoning.range(of: #"click\s*\(\s*\d+\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // Pattern: press_enter
        if reasoning.range(of: #"press[_\s]?enter"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "press_enter"
        }

        // Pattern: scroll(direction)
        if let match = reasoning.range(of: #"scroll\s*\(\s*(up|down|top|bottom)\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // Pattern: done("summary") or "task complete"
        if reasoning.range(of: #"done\s*\([\"'][^\"']+[\"']\)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            if let match = reasoning.range(of: #"done\s*\([\"'][^\"']+[\"']\)"#, options: [.regularExpression, .caseInsensitive]) {
                return String(reasoning[match])
            }
        }

        return nil
    }

    private func parseResponse(_ response: String) -> (thought: String, action: AgentAction)? {
        // Try standard THOUGHT/ACTION format first
        if let thoughtMatch = response.range(of: "THOUGHT:", options: .caseInsensitive),
           let actionMatch = response.range(of: "ACTION:", options: .caseInsensitive) {

            let thoughtStart = thoughtMatch.upperBound
            let thoughtEnd = actionMatch.lowerBound

            // Ensure THOUGHT comes before ACTION in the response
            guard thoughtEnd > thoughtStart else {
                agentLog.warning("[Agent] parseResponse: THOUGHT/ACTION markers in wrong order")
                print("[Agent] parseResponse: THOUGHT/ACTION markers in wrong order")
                // Fall through to other parsing methods
                return parseHarmonyFormat(response)
            }

            let thought = String(response[thoughtStart..<thoughtEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

            let actionString = String(response[actionMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            agentLog.debug("[Agent] parseResponse: Extracted actionString = '\(actionString)'")
            print("[Agent] parseResponse: actionString = '\(actionString)'")

            if let action = parseAction(actionString) {
                return (thought, action)
            } else {
                agentLog.warning("[Agent] parseResponse: parseAction failed for '\(actionString)'")
                print("[Agent] parseResponse: parseAction FAILED for '\(actionString)'")
            }
        }

        // Fallback: Try to parse Harmony format (OpenAI's structured output format)
        // Example: <|start|>assistant<|channel|>commentary to=browser.click <|constrain|>json<|message|>{"id":7}<|call|>
        if response.contains("<|") && response.contains("|>") {
            agentLog.info("[Agent] parseResponse: Detected Harmony format, attempting to parse")
            print("[Agent] parseResponse: Detected Harmony format, attempting to parse")

            if let result = parseHarmonyFormat(response) {
                return result
            }
        }

        agentLog.warning("[Agent] parseResponse: Could not parse response in any format")
        print("[Agent] parseResponse: Could not parse response in any format")
        return nil
    }

    /// Parse OpenAI Harmony format responses
    /// Returns (thought, action) tuple if successful
    private func parseHarmonyFormat(_ response: String) -> (thought: String, action: AgentAction)? {
        // First, check for JSON wrapper with thought/action fields
        // Example: <|message|>{"thought":"Click the button","action":"click(3)"}
        if let messageStart = response.range(of: "<|message|>"),
           let jsonStart = response[messageStart.upperBound...].firstIndex(of: "{") {

            // Find the matching closing brace
            var braceCount = 0
            var jsonEnd: String.Index?
            for idx in response.indices[jsonStart...] {
                if response[idx] == "{" { braceCount += 1 }
                else if response[idx] == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        jsonEnd = response.index(after: idx)
                        break
                    }
                }
            }

            if let jsonEnd = jsonEnd {
                let jsonString = String(response[jsonStart..<jsonEnd])
                print("[Agent] parseHarmonyFormat: Extracted JSON: \(jsonString)")

                // Try to parse as JSON with thought/action fields
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                    // Check for thought/action structure
                    if let thought = json["thought"] as? String,
                       let actionStr = json["action"] as? String {
                        print("[Agent] parseHarmonyFormat: Found thought/action JSON - thought: \(thought), action: \(actionStr)")

                        if let action = parseAction(actionStr) {
                            return (thought, action)
                        }
                    }

                    // Check for just "action" field (thought might be missing)
                    if let actionStr = json["action"] as? String {
                        print("[Agent] parseHarmonyFormat: Found action-only JSON - action: \(actionStr)")
                        if let action = parseAction(actionStr) {
                            return ("(from JSON)", action)
                        }
                    }

                    // Handle case where there's only a "thought" with no action
                    // Try to extract an action from the thought text itself
                    if let thought = json["thought"] as? String {
                        print("[Agent] parseHarmonyFormat: Found thought-only JSON, attempting to extract action from thought: \(thought)")

                        // Try to extract action patterns from the thought
                        if let extractedAction = extractActionFromReasoning(thought) {
                            print("[Agent] parseHarmonyFormat: Extracted action from thought: \(extractedAction)")
                            if let action = parseAction(extractedAction) {
                                return (thought, action)
                            }
                        }

                        // Check if the thought itself describes an action we can infer
                        let thoughtLower = thought.lowercased()
                        if thoughtLower.contains("type") && thoughtLower.contains("search") {
                            // Try to find element ID for search box mentioned in recent context
                            print("[Agent] parseHarmonyFormat: Thought mentions typing in search, but no specific action")
                        }
                        if thoughtLower.contains("press enter") || thoughtLower.contains("press_enter") {
                            return (thought, .pressEnter)
                        }
                        if thoughtLower.contains("scroll down") {
                            return (thought, .scroll(direction: .down))
                        }
                        if thoughtLower.contains("scroll up") {
                            return (thought, .scroll(direction: .up))
                        }
                    }
                }
            }
        }

        // Fall through to direct tool call patterns (browser.click, etc.)
        if let action = parseHarmonyToolCall(response) {
            return ("(Harmony tool call)", action)
        }

        // Check for commentary-only responses (no actionable content)
        if response.contains("<|channel|>commentary") {
            print("[Agent] parseHarmonyFormat: Response is commentary-only with no action")
        }

        print("[Agent] parseHarmonyFormat: Could not extract action from Harmony format")
        return nil
    }

    /// Parse direct Harmony tool calls (browser.click, browser.type, etc.)
    private func parseHarmonyToolCall(_ response: String) -> AgentAction? {
        // Handle browser.send_action format: {"action":"navigate","url":"..."}
        if response.contains("browser.send_action") {
            print("[Agent] parseHarmonyToolCall: Detected browser.send_action format")

            // Extract the JSON payload
            if let messageStart = response.range(of: "<|message|>"),
               let jsonStart = response[messageStart.upperBound...].firstIndex(of: "{") {

                // Find the matching closing brace
                var braceCount = 0
                var jsonEnd: String.Index?
                for idx in response.indices[jsonStart...] {
                    if response[idx] == "{" { braceCount += 1 }
                    else if response[idx] == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            jsonEnd = response.index(after: idx)
                            break
                        }
                    }
                }

                if let jsonEnd = jsonEnd {
                    let jsonString = String(response[jsonStart..<jsonEnd])
                    print("[Agent] parseHarmonyToolCall: send_action JSON: \(jsonString)")

                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let actionType = json["action"] as? String {

                        switch actionType.lowercased() {
                        case "navigate":
                            if let url = json["url"] as? String {
                                print("[Agent] parseHarmonyToolCall: Extracted navigate(url: \(url)) from send_action")
                                return .navigate(url: url)
                            }
                        case "click":
                            if let id = json["id"] as? Int {
                                return .click(elementId: id)
                            } else if let idStr = json["id"] as? String, let id = Int(idStr) {
                                return .click(elementId: id)
                            }
                        case "type":
                            let id: Int?
                            if let intId = json["id"] as? Int {
                                id = intId
                            } else if let strId = json["id"] as? String {
                                id = Int(strId)
                            } else {
                                id = nil
                            }
                            if let id = id, let text = json["text"] as? String {
                                return .type(elementId: id, text: text)
                            }
                        case "press_enter", "pressenter", "enter":
                            return .pressEnter
                        case "scroll":
                            if let direction = json["direction"] as? String {
                                if let dir = AgentAction.ScrollDirection(rawValue: direction.lowercased()) {
                                    return .scroll(direction: dir)
                                }
                            }
                        case "done", "complete":
                            let summary = json["summary"] as? String ?? "Task completed"
                            return .done(summary: summary)
                        default:
                            print("[Agent] parseHarmonyToolCall: Unknown action type '\(actionType)' in send_action")
                        }
                    }
                }
            }
        }

        // browser.click with JSON payload {"id": N} or {"id": "N"}
        if response.contains("browser.click") {
            // Try to extract ID (handles both integer and string formats)
            // Pattern matches: "id": 7 or "id": "7" or "id":"7"
            if let idRange = response.range(of: #""id"\s*:\s*"?(\d+)"?"#, options: .regularExpression) {
                let idSegment = String(response[idRange])
                // Extract just the digits
                if let digitRange = idSegment.range(of: #"\d+"#, options: .regularExpression) {
                    if let id = Int(idSegment[digitRange]) {
                        print("[Agent] parseHarmonyToolCall: Extracted click(id: \(id))")
                        return .click(elementId: id)
                    }
                }
            }
        }

        // browser.type with JSON payload {"id": N, "text": "..."} or {"id": "N", "text": "..."}
        if response.contains("browser.type") {
            // Extract ID (handles both integer and string formats)
            if let idRange = response.range(of: #""id"\s*:\s*"?(\d+)"?"#, options: .regularExpression),
               let textRange = response.range(of: #""text"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                let idSegment = String(response[idRange])
                var text = String(response[textRange])
                // Extract just the text value
                if let valueStart = text.range(of: ":") {
                    text = String(text[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                // Extract just the digits from ID
                if let digitRange = idSegment.range(of: #"\d+"#, options: .regularExpression) {
                    if let id = Int(idSegment[digitRange]) {
                        print("[Agent] parseHarmonyToolCall: Extracted type(id: \(id), text: \(text))")
                        return .type(elementId: id, text: text)
                    }
                }
            }
        }

        // browser.press_enter
        if response.contains("browser.press_enter") || response.contains("press_enter") {
            print("[Agent] parseHarmonyToolCall: Extracted press_enter")
            return .pressEnter
        }

        // browser.scroll
        if response.contains("browser.scroll") {
            if response.contains("\"down\"") || response.contains("down") {
                return .scroll(direction: .down)
            } else if response.contains("\"up\"") || response.contains("up") {
                return .scroll(direction: .up)
            }
        }

        // browser.navigate
        if response.contains("browser.navigate") {
            if let urlRange = response.range(of: #""url"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                var url = String(response[urlRange])
                if let valueStart = url.range(of: ":") {
                    url = String(url[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                print("[Agent] parseHarmonyToolCall: Extracted navigate(url: \(url))")
                return .navigate(url: url)
            }
        }

        // browser.done
        if response.contains("browser.done") || response.contains("task.complete") {
            // Try to extract summary
            if let summaryRange = response.range(of: #""summary"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                var summary = String(response[summaryRange])
                if let valueStart = summary.range(of: ":") {
                    summary = String(summary[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                return .done(summary: summary)
            }
            return .done(summary: "Task completed")
        }

        return nil
    }

    private func parseAction(_ actionString: String) -> AgentAction? {
        var trimmed = actionString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle multi-action responses: only parse the FIRST action
        // If there's a newline followed by another THOUGHT or ACTION, truncate there
        if let nextActionRange = trimmed.range(of: #"\n\s*(THOUGHT:|ACTION:)"#, options: .regularExpression) {
            trimmed = String(trimmed[..<nextActionRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            agentLog.info("[Agent] parseAction: Truncated multi-action response to first action: '\(trimmed)'")
            print("[Agent] parseAction: Truncated multi-action response to first action: '\(trimmed)'")
        }

        agentLog.debug("[Agent] parseAction: Attempting to parse '\(trimmed)'")
        print("[Agent] parseAction: Attempting to parse '\(trimmed)'")

        // click(id)
        if let match = trimmed.range(of: #"click\s*\(\s*(\d+)\s*\)"#, options: .regularExpression) {
            let idStr = trimmed[match].replacingOccurrences(of: "click", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let id = Int(idStr) {
                return .click(elementId: id)
            }
        }

        // type(id, "text")
        if let match = trimmed.range(of: #"type\s*\(\s*(\d+)\s*,\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let content = String(trimmed[match])
            // Extract ID and text
            if let idRange = content.range(of: #"\d+"#, options: .regularExpression),
               let textRange = content.range(of: #"[\"'](.+?)[\"']"#, options: .regularExpression) {
                let id = Int(content[idRange]) ?? 0
                var text = String(content[textRange])
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return .type(elementId: id, text: text)
            }
        }

        // press_enter
        if trimmed.lowercased().hasPrefix("press_enter") {
            return .pressEnter
        }

        // scroll(direction)
        if let match = trimmed.range(of: #"scroll\s*\(\s*(\w+)\s*\)"#, options: .regularExpression) {
            let dirStr = String(trimmed[match])
                .replacingOccurrences(of: "scroll", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if let direction = AgentAction.ScrollDirection(rawValue: dirStr) {
                return .scroll(direction: direction)
            }
        }

        // navigate("url")
        if let match = trimmed.range(of: #"navigate\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let url = String(trimmed[match])
                .replacingOccurrences(of: "navigate", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return .navigate(url: url)
        }

        // back()
        if trimmed.lowercased().hasPrefix("back()") || trimmed.lowercased().hasPrefix("back") && trimmed.count < 10 {
            return .back
        }

        // wait_for_user("reason")
        if let match = trimmed.range(of: #"wait_for_user\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let reason = String(trimmed[match])
                .replacingOccurrences(of: "wait_for_user", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return .waitForUser(reason: reason)
        }

        // wait(seconds)
        if let match = trimmed.range(of: #"wait\s*\(\s*([\d.]+)\s*\)"#, options: .regularExpression) {
            let secStr = String(trimmed[match])
                .replacingOccurrences(of: "wait", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let seconds = Double(secStr) {
                return .wait(seconds: seconds)
            }
        }

        // done("summary")
        if let match = trimmed.range(of: #"done\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let summary = String(trimmed[match])
                .replacingOccurrences(of: "done", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            agentLog.info("[Agent] parseAction: Matched done() with summary: \(summary)")
            print("[Agent] parseAction: Matched done() with summary: \(summary)")
            return .done(summary: summary)
        }

        // Log unmatched action for debugging
        agentLog.debug("[Agent] parseAction: No pattern matched for '\(trimmed)'")
        print("[Agent] parseAction: no pattern matched for '\(trimmed)'")

        // Check if it looks like a done() without quotes
        if trimmed.lowercased().hasPrefix("done") {
            print("[Agent] parseAction: Looks like done() but didn't match regex. Check for missing quotes.")
        }

        return nil
    }

    private func describeAction(_ action: AgentAction) -> String {
        switch action {
        case .click(let id):
            return "Click element #\(id)"
        case .type(let id, let text):
            return "Type \"\(text)\" into element #\(id)"
        case .pressEnter:
            return "Press Enter"
        case .scroll(let direction):
            return "Scroll \(direction.rawValue)"
        case .navigate(let url):
            return "Navigate to \(url)"
        case .back:
            return "Go back to previous page"
        case .waitForUser(let reason):
            return "Waiting for user: \(reason)"
        case .wait(let seconds):
            return "Wait \(seconds) seconds"
        case .done(let summary):
            return "Done: \(summary)"
        }
    }

    private func executeAction(_ action: AgentAction, bridge: AccessibilityBridge) async throws -> String {
        switch action {
        case .click(let elementId):
            try await bridge.click(elementId: elementId)
            try await bridge.waitForLoad(timeout: 3.0)
            return "Clicked element #\(elementId)"

        case .type(let elementId, let text):
            try await bridge.type(elementId: elementId, text: text)
            return "Typed \"\(text)\" into element #\(elementId)"

        case .pressEnter:
            try await bridge.pressEnter()
            try await bridge.waitForLoad(timeout: 3.0)
            return "Pressed Enter"

        case .scroll(let direction):
            switch direction {
            case .up:
                try await bridge.scroll(deltaY: -300)
            case .down:
                try await bridge.scroll(deltaY: 300)
            case .top:
                try await bridge.scrollToTop()
            case .bottom:
                try await bridge.scrollToBottom()
            }
            return "Scrolled \(direction.rawValue)"

        case .navigate(let urlString):
            var url = urlString
            if !url.contains("://") {
                url = "https://\(url)"
            }
            if let parsedURL = URL(string: url) {
                // Navigate the bound tab, not the active tab
                guard let boundTabId = boundTabId,
                      let tab = browserState.tab(for: boundTabId) else {
                    throw AgentError.webViewUnavailable
                }
                tab.load(parsedURL.absoluteString)
                try await bridge.waitForLoad(timeout: 10.0)
                return "Navigated to \(url)"
            } else {
                throw AgentError.navigationFailed("Invalid URL: \(urlString)")
            }

        case .back:
            guard let boundTabId = boundTabId,
                  let tab = browserState.tab(for: boundTabId) else {
                throw AgentError.webViewUnavailable
            }
            guard tab.canGoBack else {
                return "Cannot go back - no history"
            }
            tab.goBack()
            try await bridge.waitForLoad(timeout: 5.0)
            // Clear recent actions when backing out to give fresh perspective
            recentNormalizedActions = []
            return "Navigated back to previous page"

        case .waitForUser(let reason):
            isWaitingForUser = true
            waitingReason = reason
            agentLog.info("[Agent] Waiting for user action: \(reason)")
            print("[Agent] ⏸️ Waiting for user: \(reason)")

            // Wait for the page to change (user solved captcha, etc.)
            // Poll every 2 seconds for up to 2 minutes
            let startURL = try? await bridge.snapshot().url
            for _ in 0..<60 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000_000)

                // Check if page URL changed
                if let currentURL = try? await bridge.snapshot().url,
                   currentURL != startURL {
                    isWaitingForUser = false
                    waitingReason = ""
                    return "User completed action - page changed"
                }

                // Also check if page content changed significantly
                // (some captchas stay on same URL but content changes)
            }

            isWaitingForUser = false
            waitingReason = ""
            return "Timed out waiting for user action"

        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return "Waited \(seconds) seconds"

        case .done(let summary):
            return summary
        }
    }

    // MARK: - LLM Integration

    private func callLLM(prompt: String) async throws -> String {
        guard let baseURL = settings.llmBaseURL else {
            throw AgentError.llmNotConfigured
        }

        let endpoint = baseURL.appendingPathComponent("chat/completions")

        let body: [String: Any] = [
            "model": settings.selectedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 4000  // Increased for reasoning models that use tokens for chain-of-thought
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        // Retry logic for transient errors (5xx, network issues)
        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Add API key if configured
                if settings.useAPIKey && settings.hasAPIKey {
                    request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
                }

                request.httpBody = bodyData

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    agentLog.error("[Agent] callLLM: Invalid HTTP response type")
                    print("[Agent] callLLM: Invalid HTTP response type")
                    throw AgentError.llmRequestFailed("Invalid response")
                }

                agentLog.debug("[Agent] callLLM: HTTP status \(httpResponse.statusCode)")
                print("[Agent] callLLM: HTTP status \(httpResponse.statusCode)")

                // Handle retryable errors (5xx server errors, 429 rate limit)
                if httpResponse.statusCode >= 500 || httpResponse.statusCode == 429 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    agentLog.warning("[Agent] callLLM: HTTP \(httpResponse.statusCode) (attempt \(attempt)/\(maxRetries))")

                    // Log detailed error info for debugging
                    print("[Agent] callLLM: ⚠️ HTTP \(httpResponse.statusCode) (attempt \(attempt)/\(maxRetries))")
                    print("[Agent] callLLM: Request details:")
                    print("  - Endpoint: \(endpoint)")
                    print("  - Model: \(settings.selectedModel)")
                    print("  - Prompt length: \(prompt.count) chars")
                    print("  - max_tokens: 4000")
                    print("[Agent] callLLM: Error response body:")
                    print(errorBody)

                    if attempt < maxRetries {
                        // Exponential backoff: 1s, 2s, 4s
                        let backoffSeconds = pow(2.0, Double(attempt - 1))
                        try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                        continue
                    } else {
                        throw AgentError.llmRequestFailed("HTTP \(httpResponse.statusCode) after \(maxRetries) retries: \(errorBody)")
                    }
                }

                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    agentLog.error("[Agent] callLLM: HTTP error \(httpResponse.statusCode): \(errorMessage)")
                    print("[Agent] callLLM: HTTP error \(httpResponse.statusCode): \(errorMessage)")
                    throw AgentError.llmRequestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
                }

                // Success - parse the response (rest of the function continues below)
                return try await parseLLMResponse(data: data)

            } catch let error as AgentError {
                lastError = error
                // Don't retry AgentErrors that aren't network-related
                if case .llmRequestFailed(let msg) = error, msg.contains("HTTP 5") || msg.contains("HTTP 429") {
                    continue
                }
                throw error
            } catch {
                // Network errors - retry
                lastError = error
                agentLog.warning("[Agent] callLLM: Network error (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription)")
                print("[Agent] callLLM: ⚠️ Network error (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription)")

                if attempt < maxRetries {
                    let backoffSeconds = pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                    continue
                }
            }
        }

        throw lastError ?? AgentError.llmRequestFailed("Unknown error after \(maxRetries) retries")
    }

    private func parseLLMResponse(data: Data) async throws -> String {

        // Log raw response for debugging
        let rawResponse = String(data: data, encoding: .utf8) ?? "<binary data>"
        agentLog.debug("[Agent] callLLM: Raw JSON response (first 500 chars): \(String(rawResponse.prefix(500)))")
        print("[Agent] callLLM: Raw JSON response:\n\(rawResponse)")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            agentLog.error("[Agent] callLLM: Failed to parse JSON structure. Raw: \(rawResponse)")
            print("[Agent] callLLM: JSON PARSE FAILED. Raw response:\n\(rawResponse)")
            throw AgentError.invalidLLMResponse("Could not parse response")
        }

        // Check finish_reason for truncation
        let finishReason = firstChoice["finish_reason"] as? String ?? "unknown"
        if finishReason == "length" {
            agentLog.warning("[Agent] callLLM: Response truncated (finish_reason=length)")
            print("[Agent] callLLM: ⚠️ Response truncated due to token limit")

            // If content is null and response was truncated, don't try to use reasoning_content
            // The reasoning chain is incomplete and will likely fail to parse
            if message["content"] == nil || (message["content"] as? String) == nil {
                print("[Agent] callLLM: Truncated response with no content - will retry")
                throw AgentError.invalidLLMResponse("Response truncated before generating action (finish_reason=length)")
            }
        }

        // For reasoning models (like gpt-oss-20b):
        // - "content" contains the final formatted response (THOUGHT/ACTION)
        // - "reasoning_content" contains internal chain-of-thought
        // We prefer "content", but fall back to "reasoning_content" if content is null

        if let content = message["content"] as? String {
            // Normal case: content field has the formatted response
            return content
        }

        // Content is null - try reasoning_content as fallback
        if let reasoningContent = message["reasoning_content"] as? String {
            agentLog.warning("[Agent] callLLM: content is null, using reasoning_content as fallback")
            print("[Agent] callLLM: ⚠️ content is null, trying reasoning_content")

            // Check if reasoning_content has THOUGHT/ACTION markers (sometimes it does)
            if reasoningContent.range(of: "THOUGHT:", options: .caseInsensitive) != nil &&
               reasoningContent.range(of: "ACTION:", options: .caseInsensitive) != nil {
                print("[Agent] callLLM: reasoning_content contains THOUGHT/ACTION markers, using it")
                return reasoningContent
            }

            // Try to extract an action from the reasoning content
            // Look for patterns like "Let's do navigate" or "We should type" or "click(N)"
            if let extractedAction = extractActionFromReasoning(reasoningContent) {
                print("[Agent] callLLM: Extracted action from reasoning_content: \(extractedAction)")
                return "THOUGHT: (extracted from reasoning)\nACTION: \(extractedAction)"
            }

            // reasoning_content exists but couldn't extract an action
            print("[Agent] callLLM: reasoning_content lacks markers and no action extractable")
            // Don't return raw reasoning - it will just fail to parse
            // Instead, throw an error so we can retry
            throw AgentError.invalidLLMResponse("Model returned only reasoning_content without actionable output")
        }

        // Both content and reasoning_content are null/missing
        agentLog.error("[Agent] callLLM: Both content and reasoning_content are null")
        print("[Agent] callLLM: ❌ Both content and reasoning_content are null (finish_reason: \(finishReason))")
        throw AgentError.invalidLLMResponse("No content in response (finish_reason: \(finishReason))")
    }
}
