import Foundation
import FoundationModels
import SwiftUI

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

/// Modifier keys that can be held during a click action
struct ClickModifiers: Equatable {
    var shift: Bool = false
    var command: Bool = false  // metaKey on web
    var control: Bool = false
    var option: Bool = false   // altKey on web
    static let none = ClickModifiers()

    /// Parse from an array of modifier name strings (e.g. ["shift", "command"])
    static func from(_ names: [String]) -> ClickModifiers {
        var m = ClickModifiers()
        for name in names {
            switch name.lowercased() {
            case "shift": m.shift = true
            case "command", "cmd", "meta": m.command = true
            case "control", "ctrl": m.control = true
            case "option", "alt": m.option = true
            default: break
            }
        }
        return m
    }

    /// Parse from a "+" delimited string like "shift+command"
    static func from(_ string: String) -> ClickModifiers {
        from(string.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) })
    }
}

/// Available actions the agent can take
enum AgentAction: Equatable {
    case click(elementId: Int, modifiers: ClickModifiers = .none)
    case type(elementId: Int, text: String)
    case pressEnter
    case scroll(direction: ScrollDirection)
    case navigate(url: String)
    case back
    case waitForUser(reason: String)
    case wait(seconds: Double)
    case readText(elementId: Int)
    case newTab
    case openTab(url: String)
    case switchTab(index: Int)
    case extractContent
    case readLinks
    case done(summary: String)

    enum ScrollDirection: String {
        case up, down, top, bottom
    }
}

/// Batched state for AgentEngine to reduce SwiftUI redraws
/// All state changes are published as a single update
struct AgentState: Equatable {
    var isRunning: Bool = false
    var currentTask: String = ""
    var steps: [AgentStep] = []
    var progress: String = ""
    var error: String?
    var boundTabId: UUID?
    var isWaitingForUser: Bool = false
    var waitingReason: String = ""
    var guardrailWarning: String?
    var streamingThought: String?

    static func == (lhs: AgentState, rhs: AgentState) -> Bool {
        lhs.isRunning == rhs.isRunning &&
        lhs.currentTask == rhs.currentTask &&
        lhs.steps.count == rhs.steps.count &&
        lhs.progress == rhs.progress &&
        lhs.error == rhs.error &&
        lhs.boundTabId == rhs.boundTabId &&
        lhs.isWaitingForUser == rhs.isWaitingForUser &&
        lhs.waitingReason == rhs.waitingReason &&
        lhs.guardrailWarning == rhs.guardrailWarning &&
        lhs.streamingThought == rhs.streamingThought
    }
}

/// The ReAct agent engine for browser automation
@MainActor
@Observable
class AgentEngine {
    // MARK: - Observable State (per-property tracking via @Observable)

    private(set) var isRunning: Bool = false
    private(set) var currentTask: String = ""
    var steps: [AgentStep] = []
    private(set) var progress: String = ""
    private(set) var error: String?
    private(set) var boundTabId: UUID?
    private(set) var isWaitingForUser: Bool = false
    private(set) var waitingReason: String = ""
    private(set) var guardrailWarning: String?
    private(set) var streamingThought: String?

    // MARK: - Dependencies (excluded from observation)

    @ObservationIgnored private let browserState: BrowserState
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let llmClient: any AgentLLMProvider
    @ObservationIgnored private let bridgeProvider: any BrowserBridgeProvider
    @ObservationIgnored private let loopDetector = AgentLoopDetector()
    @ObservationIgnored private var currentTaskHandle: Task<AgentResult, Never>?
    @ObservationIgnored private weak var boundTab: Tab?
    @ObservationIgnored private var tabClosureObserverTask: Task<Void, Never>?

    // MARK: - Configuration (excluded from observation)

    /// Maximum number of steps the agent can take before stopping
    @ObservationIgnored var maxSteps: Int = 50

    /// Maximum wall-clock time (in seconds) for a task before stopping
    @ObservationIgnored var taskTimeout: TimeInterval = 300

    /// Maximum number of times done() verification can reject and continue
    @ObservationIgnored private let maxDoneRejections = 2

    /// The threshold (0.0-1.0) at which to show warnings (default 80%)
    @ObservationIgnored private let warningThreshold: Double = 0.8

    /// Number of steps remaining before the limit is reached
    var stepsRemaining: Int {
        max(0, maxSteps - currentStepCount)
    }

    /// Current step count (tracked during execution)
    @ObservationIgnored private(set) var currentStepCount: Int = 0

    // MARK: - Initialization

    init(browserState: BrowserState, settings: AppSettings) {
        self.browserState = browserState
        self.settings = settings
        self.llmClient = OnDeviceLLM.shared
        self.bridgeProvider = browserState
    }

    /// Test initializer allowing injection of mock dependencies
    init(browserState: BrowserState, llmClient: any AgentLLMProvider, bridgeProvider: any BrowserBridgeProvider) {
        self.browserState = browserState
        self.settings = AppSettings.shared
        self.llmClient = llmClient
        self.bridgeProvider = bridgeProvider
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

        guard let activeTab = browserState.activeTab else {
            return AgentResult(success: false, summary: "No active tab", steps: [])
        }

        boundTabId = activeTab.id
        boundTab = activeTab
        activeTab.hasActiveAgent = true
        activeTab.agentProgress = "Starting..."

        setupTabClosureObserver()

        isRunning = true
        currentTask = task
        steps = []
        error = nil
        progress = "Starting..."

        let taskHandle = Task { () -> AgentResult in
            defer { self.resetState() }
            do {
                let result = try await executeTask(task)
                return result
            } catch {
                Log.Agent.error("Task failed with error: \(error.localizedDescription)")
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
        return result
    }

    /// Cancel the current task
    func cancel() {
        currentTaskHandle?.cancel()
        currentTaskHandle = nil
        cleanupTabBinding()
        isRunning = false
        progress = "Cancelled"
    }

    // MARK: - State Management

    /// Atomically reset all mutable state after a task completes
    private func resetState() {
        cleanupTabBinding()
        isRunning = false
        guardrailWarning = nil
        streamingThought = nil
        currentStepCount = 0
        loopDetector.reset()
    }

    /// Set up observer to detect when the bound tab is closed
    private func setupTabClosureObserver() {
        tabClosureObserverTask?.cancel()
        tabClosureObserverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let tabs = await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.browserState.tabs
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume(returning: self.browserState.tabs)
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                guard let boundId = self.boundTabId, self.isRunning else { continue }
                if !tabs.contains(where: { $0.id == boundId }) {
                    Log.Agent.warning("Bound tab was closed, cancelling agent")
                    self.error = "Tab was closed"
                    let errorStep = AgentStep(type: .error, content: "Task cancelled: tab was closed", timestamp: Date())
                    self.steps.append(errorStep)
                    self.cancel()
                    return
                }
            }
        }
    }

    /// Clean up tab binding when agent finishes
    private func cleanupTabBinding() {
        tabClosureObserverTask?.cancel()
        tabClosureObserverTask = nil

        if let tab = boundTab {
            tab.hasActiveAgent = false
            tab.agentProgress = ""
        }

        boundTab = nil
        boundTabId = nil
    }

    // MARK: - Streaming LLM

    /// Call the LLM with streaming, providing real-time thought feedback.
    /// Falls back to non-streaming structured completion on stream error.
    private func callLLMWithStreaming(prompt: String, systemPrompt: String) async throws -> GeneratedAgentDecision {
        do {
            var latestRawContent: GeneratedContent?

            defer { streamingThought = nil }

            for try await rawContent in llmClient.stream(
                prompt: prompt,
                systemPrompt: systemPrompt,
                generating: GeneratedAgentDecision.self
            ) {
                latestRawContent = rawContent

                if let thought = try? rawContent.value(String.self, forProperty: "thought") {
                    streamingThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard let latestRawContent else {
                throw AgentError.invalidLLMResponse("Empty streaming response")
            }

            return try latestRawContent.value(GeneratedAgentDecision.self)
        } catch {
            Log.Agent.warning("Streaming failed, falling back to non-streaming: \(error.localizedDescription)")
            streamingThought = nil
            return try await llmClient.complete(
                prompt: prompt,
                systemPrompt: systemPrompt,
                generating: GeneratedAgentDecision.self
            )
        }
    }

    // MARK: - Task Execution

    /// Validates that the bound tab still exists and returns it
    private func requireBoundTab() throws -> Tab {
        guard let tab = boundTab,
              let tabId = boundTabId,
              browserState.tabs.contains(where: { $0.id == tabId }) else {
            throw AgentError.tabClosed
        }
        return tab
    }

    private func executeTask(_ task: String) async throws -> AgentResult {
        var iteration = 0
        var doneRejections = 0
        currentStepCount = 0
        let startTime = Date()
        Log.Agent.info("Starting task: \(task) (maxSteps=\(maxSteps), timeout=\(Int(taskTimeout))s)")

        loopDetector.reset()
        isWaitingForUser = false
        waitingReason = ""
        guardrailWarning = nil

        guard let tabId = boundTabId else {
            throw AgentError.webViewUnavailable
        }

        while iteration < maxSteps {
            // Check wall-clock timeout
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > taskTimeout {
                Log.Agent.error("Task exceeded wall-clock timeout of \(Int(taskTimeout))s")
                let errorStep = AgentStep(type: .error, content: "Task stopped: exceeded \(Int(taskTimeout / 60)) minute time limit", timestamp: Date())
                steps.append(errorStep)
                throw AgentError.timeout("Task exceeded \(Int(taskTimeout / 60)) minute time limit")
            }
            try Task.checkCancellation()

            iteration += 1
            currentStepCount = iteration

            // Check guardrail warnings
            let stepRatio = Double(iteration) / Double(maxSteps)
            let timeRatio = elapsed / taskTimeout
            if stepRatio >= warningThreshold {
                guardrailWarning = "Approaching step limit: \(stepsRemaining) steps remaining"
            } else if timeRatio >= warningThreshold {
                let remaining = Int(taskTimeout - elapsed)
                guardrailWarning = "Approaching time limit: \(remaining)s remaining"
            } else {
                guardrailWarning = nil
            }

            let progressText = "Step \(iteration)/\(maxSteps)"
            progress = progressText

            if let tab = boundTab {
                tab.agentProgress = progressText
            }

            // 1. Observe - Get page snapshot
            guard let bridge = bridgeProvider.bridge(for: tabId) else {
                throw AgentError.webViewUnavailable
            }

            let snapshot = try await bridge.snapshot()

            // Track URL for progress detection
            loopDetector.recordURL(snapshot.url)

            let observationStep = AgentStep(
                type: .observation,
                content: "Page: \(snapshot.title)\nURL: \(snapshot.url)\n\(snapshot.elements.count) interactive elements",
                timestamp: Date()
            )
            steps.append(observationStep)

            // 2. Think - Ask LLM for next action
            let prompt = AgentPromptBuilder.buildPrompt(task: task, snapshot: snapshot, previousSteps: steps)
            let recentErrors = steps.suffix(6).filter { $0.type == .error }.count
            let dynamicSystemPrompt = AgentPromptBuilder.buildSystemPrompt(
                stepsRemaining: stepsRemaining,
                maxSteps: maxSteps,
                recentErrors: recentErrors
            )
            Log.Agent.debug("Sending prompt to LLM (length: \(prompt.count) chars)")
            let llmDecision = try await callLLMWithStreaming(prompt: prompt, systemPrompt: dynamicSystemPrompt)

            // Decode the structured decision into the domain action model
            let thought: String
            let action: AgentAction
            do {
                (thought, action) = try llmDecision.toDecision()
            } catch {
                let failureCount = loopDetector.recordParseFailure()
                let maxFailures = loopDetector.maxConsecutiveParseFailures
                Log.Agent.warning("Structured decision failed validation (attempt \(failureCount)/\(maxFailures)): \(error.localizedDescription)")

                if failureCount >= maxFailures {
                    Log.Agent.error("Max consecutive parse failures reached, aborting")
                    let errorStep = AgentStep(type: .error, content: "Failed to parse LLM response after \(maxFailures) attempts", timestamp: Date())
                    steps.append(errorStep)
                    throw AgentError.invalidLLMResponse("Unable to parse response after \(maxFailures) attempts")
                }

                let backoffSeconds = pow(2.0, Double(failureCount - 1))
                Log.Agent.info("Backing off for \(backoffSeconds)s before retry")
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))

                let errorStep = AgentStep(type: .error, content: "Failed to parse LLM response (retrying after \(Int(backoffSeconds))s backoff...)", timestamp: Date())
                steps.append(errorStep)
                continue
            }

            loopDetector.resetParseFailures()
            Log.Agent.info("Parsed - Thought: \(thought), Action: \(String(describing: action))")

            let thoughtStep = AgentStep(type: .thought, content: thought, timestamp: Date())
            steps.append(thoughtStep)

            // Build element ID map for O(1) lookup (needed for descriptive action labels and loop detection)
            let elementById = Dictionary(uniqueKeysWithValues: snapshot.elements.map { ($0.id, $0) })

            let actionDescription = describeAction(action, elementById: elementById)
            let actionStep = AgentStep(type: .action, content: actionDescription, timestamp: Date())
            steps.append(actionStep)

            // Build normalized action for loop detection
            var elementDescription: String? = nil
            if case .click(let elementId, _) = action {
                if let element = elementById[elementId] {
                    elementDescription = "\(element.tag):\(element.text ?? element.ariaLabel ?? element.placeholder ?? "unknown")"
                }
            }
            let normalizedAction = NormalizedAction(from: action, elementDescription: elementDescription)
            loopDetector.recordAction(normalizedAction)

            // Enhanced loop detection
            if let loopType = loopDetector.detectLoop() {
                Log.Agent.warning("Detected stuck loop: \(loopType)")

                if loopDetector.loopRecoveryAttempts < loopDetector.maxLoopRecoveryAttempts {
                    let attempt = loopDetector.recordRecoveryAttempt()
                    let canGoBack = boundTab?.canGoBack ?? false
                    let strategy = loopDetector.suggestRecovery(loopType: loopType, canGoBack: canGoBack)
                    Log.Agent.warning("Stuck loop detected (\(loopType)) - attempting recovery \(attempt)/\(loopDetector.maxLoopRecoveryAttempts) via \(strategy)")

                    // Surface loop status in UI
                    progress = "Agent appears stuck, attempting recovery..."
                    if let tab = boundTab {
                        tab.agentProgress = "Recovering from loop..."
                    }

                    switch strategy {
                    case .goBack:
                        let recoveryStep = AgentStep(type: .action, content: "Loop detected (\(loopType)), going back to try different approach", timestamp: Date())
                        steps.append(recoveryStep)

                        boundTab?.goBack()
                        try await bridge.waitForLoad(timeout: 5.0)
                        loopDetector.clearActions()

                        let resultStep = AgentStep(type: .result, content: "Navigated back after loop detection", timestamp: Date())
                        steps.append(resultStep)

                        try await Task.sleep(nanoseconds: 300_000_000)
                        continue

                    case .scrollDown:
                        let recoveryStep = AgentStep(type: .action, content: "Loop detected (\(loopType)), scrolling down to find new elements", timestamp: Date())
                        steps.append(recoveryStep)

                        try await bridge.scroll(deltaY: 400)
                        loopDetector.clearActions()

                        let resultStep = AgentStep(type: .result, content: "Scrolled down after loop detection to reveal new elements", timestamp: Date())
                        steps.append(resultStep)

                        try await Task.sleep(nanoseconds: 300_000_000)
                        continue

                    case .admitFailure(let reason):
                        Log.Agent.warning("Recovery not possible: \(reason)")
                        // Fall through to forced completion below
                        break
                    }
                }

                Log.Agent.warning("Stuck loop detected (\(loopType)) - forcing completion")
                let doneStep = AgentStep(type: .done, content: "Task ended: \(loopType)", timestamp: Date())
                steps.append(doneStep)
                return AgentResult(success: false, summary: "Agent got stuck: \(loopType)", steps: steps)
            }

            // 3. Act - Execute the action
            do {
                let actionResult = try await executeAction(action, bridge: bridge, elementById: elementById)

                if case .done(let summary) = action {
                    // Post-done() verification
                    if doneRejections < maxDoneRejections {
                        if let rejection = await verifyDoneCondition(bridge: bridge) {
                            doneRejections += 1
                            Log.Agent.warning("done() rejected (\(doneRejections)/\(maxDoneRejections)): \(rejection)")
                            let correctionStep = AgentStep(type: .error, content: "Verification failed: \(rejection) Do NOT call done() again immediately. Instead, take a corrective action (navigate, scroll, click, or try a different approach). If the task truly cannot be completed, call done(\"Unable to complete: \(rejection)\").", timestamp: Date())
                            steps.append(correctionStep)
                            continue
                        }
                    }

                    Log.Agent.info("Task completed successfully: \(summary)")
                    let doneStep = AgentStep(type: .done, content: summary, timestamp: Date())
                    steps.append(doneStep)
                    return AgentResult(success: true, summary: summary, steps: steps)
                }

                let resultStep = AgentStep(type: .result, content: actionResult.message, timestamp: Date())
                steps.append(resultStep)

                // Adaptive delay based on what changed
                if let delta = actionResult.delta {
                    if delta.urlChanged {
                        // Already waited in waitForLoad, no extra delay needed
                    } else if delta.significantDOMChange {
                        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    } else {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                } else {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms default
                }

            } catch {
                let mappedMessage = ActionErrorMapper.mapError(error, action: action)
                let errorStep = AgentStep(type: .error, content: mappedMessage, timestamp: Date())
                steps.append(errorStep)
            }
        }

        Log.Agent.error("Max steps (\(self.maxSteps)) reached without completion")
        let errorStep = AgentStep(type: .error, content: "Task stopped: reached maximum of \(maxSteps) steps", timestamp: Date())
        steps.append(errorStep)
        throw AgentError.maxIterationsReached
    }

    // MARK: - Action Execution

    /// Build a human-readable description of an action, using element info from the snapshot when available
    private func describeAction(_ action: AgentAction, elementById: [Int: PageElement]? = nil) -> String {
        switch action {
        case .click(let id, let modifiers):
            let modDesc = modifiers == .none ? "" : " (with modifiers)"
            if let elements = elementById, let el = elements[id] {
                let label = el.text ?? el.ariaLabel ?? el.placeholder ?? el.tag
                return "Clicking '\(label)'\(modDesc)"
            }
            return "Clicking element #\(id)\(modDesc)"
        case .type(let id, let text):
            if let elements = elementById, let el = elements[id] {
                let label = el.ariaLabel ?? el.placeholder ?? el.tag
                return "Typing \"\(text)\" into '\(label)'"
            }
            return "Typing \"\(text)\" into element #\(id)"
        case .pressEnter:
            return "Pressing Enter"
        case .scroll(let direction):
            return "Scrolling \(direction.rawValue)"
        case .navigate(let url):
            if let host = URL(string: url)?.host {
                return "Navigating to \(host)"
            }
            return "Navigating to \(url)"
        case .back:
            return "Going back to previous page"
        case .waitForUser(let reason):
            return "Waiting for user: \(reason)"
        case .wait(let seconds):
            return "Waiting \(String(format: "%.0f", seconds)) seconds"
        case .readText(let id):
            if let elements = elementById, let el = elements[id] {
                let label = el.text ?? el.ariaLabel ?? el.tag
                return "Reading text near '\(label)'"
            }
            return "Reading text near element #\(id)"
        case .newTab:
            return "Opening new blank tab"
        case .openTab(let url):
            if let host = URL(string: url)?.host {
                return "Opening new tab: \(host)"
            }
            return "Opening new tab: \(url)"
        case .switchTab(let index):
            return "Switching to tab #\(index)"
        case .extractContent:
            return "Extracting full page content"
        case .readLinks:
            return "Reading all links on page"
        case .done(let summary):
            return "Done: \(summary)"
        }
    }

    /// Result of executing an action, including feedback delta
    struct ActionResult {
        let message: String
        let delta: ActionDelta?
    }

    private func executeAction(_ action: AgentAction, bridge: any BrowserBridge, elementById: [Int: PageElement] = [:]) async throws -> ActionResult {
        // Capture pre-action state for delta computation
        let preState = await bridge.capturePreActionState()

        switch action {
        case .click(let elementId, let modifiers):
            // Re-validate element before clicking (handles SPA re-renders)
            let element = elementById[elementId]
            let resolvedId = try await bridge.revalidateElement(
                elementId: elementId,
                expectedTag: element?.tag,
                expectedText: element?.text
            )
            try await bridge.click(elementId: resolvedId, modifiers: modifiers)
            try await bridge.waitForLoad(timeout: 3.0)
            let delta = await bridge.quickDelta(before: preState)
            let reMatchNote = resolvedId != elementId ? " (re-matched from #\(elementId))" : ""
            return ActionResult(message: "Clicked element #\(resolvedId)\(reMatchNote). \(delta.description)", delta: delta)

        case .type(let elementId, let text):
            // Re-validate element before typing (handles SPA re-renders)
            let element = elementById[elementId]
            let resolvedId = try await bridge.revalidateElement(
                elementId: elementId,
                expectedTag: element?.tag,
                expectedText: element?.placeholder ?? element?.ariaLabel
            )
            try await bridge.type(elementId: resolvedId, text: text)
            let delta = await bridge.quickDelta(before: preState)
            let reMatchNote = resolvedId != elementId ? " (re-matched from #\(elementId))" : ""
            return ActionResult(message: "Typed \"\(text)\" into element #\(resolvedId)\(reMatchNote). \(delta.description)", delta: delta)

        case .pressEnter:
            try await bridge.pressEnter()
            try await bridge.waitForLoad(timeout: 3.0)
            let delta = await bridge.quickDelta(before: preState)
            return ActionResult(message: "Pressed Enter. \(delta.description)", delta: delta)

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
            let delta = await bridge.quickDelta(before: preState)
            return ActionResult(message: "Scrolled \(direction.rawValue). \(delta.description)", delta: delta)

        case .navigate(let urlString):
            let validatedURL = try NavigationPolicy.validate(urlString)
            let tab = try requireBoundTab()
            tab.load(validatedURL.absoluteString)
            try await bridge.waitForLoad(timeout: 10.0)
            let delta = await bridge.quickDelta(before: preState)
            return ActionResult(message: "Navigated to \(validatedURL.absoluteString). \(delta.description)", delta: delta)

        case .back:
            let tab = try requireBoundTab()
            guard tab.canGoBack else {
                return ActionResult(message: "Cannot go back - no history", delta: nil)
            }
            tab.goBack()
            try await bridge.waitForLoad(timeout: 5.0)
            loopDetector.clearActions()
            let delta = await bridge.quickDelta(before: preState)
            return ActionResult(message: "Navigated back to previous page. \(delta.description)", delta: delta)

        case .waitForUser(let reason):
            isWaitingForUser = true
            waitingReason = reason
            Log.Agent.info("Waiting for user action: \(reason)")

            let startState = preState
            for _ in 0..<60 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000_000)

                let currentState = await bridge.capturePreActionState()
                let urlChanged = currentState.url != startState.url
                let captchaGone = startState.captchaDetected && !currentState.captchaDetected
                let domShift = currentState.elementCount >= 0 && startState.elementCount >= 0 && abs(currentState.elementCount - startState.elementCount) > 5

                if urlChanged || captchaGone || domShift {
                    isWaitingForUser = false
                    waitingReason = ""
                    let delta = await bridge.quickDelta(before: startState)
                    return ActionResult(message: "User completed action. \(delta.description)", delta: delta)
                }
            }

            isWaitingForUser = false
            waitingReason = ""
            return ActionResult(message: "Timed out waiting for user action", delta: nil)

        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            let delta = await bridge.quickDelta(before: preState)
            return ActionResult(message: "Waited \(seconds) seconds. \(delta.description)", delta: delta)

        case .readText(let elementId):
            let text = try await bridge.readText(elementId: elementId)
            if text.isEmpty {
                return ActionResult(message: "No text found near element #\(elementId).", delta: nil)
            }
            return ActionResult(message: "Text near element #\(elementId): \(text)", delta: nil)

        case .newTab:
            browserState.addTab()
            return ActionResult(message: "Opened new blank tab. Agent remains on current tab.", delta: nil)

        case .openTab(let urlString):
            let validatedURL = try NavigationPolicy.validate(urlString)
            browserState.addTab(withURL: validatedURL)
            return ActionResult(message: "Opened new tab with \(validatedURL.absoluteString). Agent remains on current tab.", delta: nil)

        case .switchTab(let index):
            let zeroBasedIndex = index - 1
            guard zeroBasedIndex >= 0, zeroBasedIndex < browserState.tabs.count else {
                return ActionResult(message: "Invalid tab index \(index). There are \(browserState.tabs.count) tabs (1-\(browserState.tabs.count)).", delta: nil)
            }
            let targetTab = browserState.tabs[zeroBasedIndex]

            // Clear agent flag on old tab
            if let oldTab = boundTab {
                oldTab.hasActiveAgent = false
            }

            // Rebind to the new tab
            browserState.selectTab(targetTab.id)
            boundTab = targetTab
            boundTabId = targetTab.id
            targetTab.hasActiveAgent = true
            targetTab.agentProgress = progress

            let tabLabel = targetTab.title.isEmpty ? (targetTab.url?.absoluteString ?? "untitled") : targetTab.title
            return ActionResult(message: "Switched to tab #\(index): \(tabLabel)", delta: nil)

        case .extractContent:
            let tab = try requireBoundTab()
            let extractor = ContentExtractor()
            if let pageContext = await extractor.extractContent(from: tab) {
                var text = pageContext.textContent
                if text.count > 4000 {
                    text = String(text.prefix(4000)) + "... (truncated)"
                }
                return ActionResult(message: "Page content (\(pageContext.title)):\n\(text)", delta: nil)
            }
            return ActionResult(message: "Could not extract page content.", delta: nil)

        case .readLinks:
            let links = try await bridge.getPageLinks()
            if links.isEmpty {
                return ActionResult(message: "No links found on this page.", delta: nil)
            }
            // Truncate to last complete line within 3000 chars to keep prompt manageable
            var linksText = links
            if linksText.count > 3000 {
                let truncated = String(linksText.prefix(3000))
                if let lastNewline = truncated.lastIndex(of: "\n") {
                    linksText = String(truncated[...lastNewline])
                } else {
                    linksText = truncated
                }
                linksText += "... (more links on page)"
            }
            return ActionResult(message: "Links on page:\n\(linksText)", delta: nil)

        case .done(let summary):
            return ActionResult(message: summary, delta: nil)
        }
    }

    // MARK: - Post-done() Verification

    /// Lightweight heuristic check before accepting done(). Returns rejection reason or nil if OK.
    private func verifyDoneCondition(bridge: any BrowserBridge) async -> String? {
        do {
            let snapshot = try await bridge.snapshot()

            // Check if page shows error
            let title = snapshot.title.lowercased()
            let url = snapshot.url.lowercased()
            if title.contains("404") || title.contains("not found") || title.contains("error") ||
               url.contains("/404") || url.contains("/error") {
                return "The page appears to show an error (title: \"\(snapshot.title)\")."
            }

            // Check if captcha is still present
            if snapshot.captchaDetected {
                return "A captcha/challenge is still present on the page. It must be resolved first."
            }

            // Check if page has loaded (very few elements suggests blank/loading page)
            if snapshot.elements.count <= 3 {
                return "The page appears to still be loading (only \(snapshot.elements.count) elements found)."
            }

            return nil
        } catch {
            // If we can't even take a snapshot, don't block done()
            Log.Agent.warning("Verification snapshot failed: \(error.localizedDescription)")
            return nil
        }
    }
}
