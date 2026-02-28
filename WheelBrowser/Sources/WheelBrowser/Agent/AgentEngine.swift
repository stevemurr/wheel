import Foundation
import SwiftUI
import Combine

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

    static func == (lhs: AgentState, rhs: AgentState) -> Bool {
        lhs.isRunning == rhs.isRunning &&
        lhs.currentTask == rhs.currentTask &&
        lhs.steps.count == rhs.steps.count &&
        lhs.progress == rhs.progress &&
        lhs.error == rhs.error &&
        lhs.boundTabId == rhs.boundTabId &&
        lhs.isWaitingForUser == rhs.isWaitingForUser &&
        lhs.waitingReason == rhs.waitingReason &&
        lhs.guardrailWarning == rhs.guardrailWarning
    }
}

/// The ReAct agent engine for browser automation
@MainActor
class AgentEngine: ObservableObject {
    // MARK: - Published State (batched for performance)

    @Published private(set) var state = AgentState()

    // MARK: - Computed Properties for Backwards Compatibility

    var isRunning: Bool {
        get { state.isRunning }
        set { state.isRunning = newValue }
    }

    var currentTask: String {
        get { state.currentTask }
        set { state.currentTask = newValue }
    }

    var steps: [AgentStep] {
        get { state.steps }
        set { state.steps = newValue }
    }

    var progress: String {
        get { state.progress }
        set { state.progress = newValue }
    }

    var error: String? {
        get { state.error }
        set { state.error = newValue }
    }

    var boundTabId: UUID? {
        get { state.boundTabId }
        set { state.boundTabId = newValue }
    }

    var isWaitingForUser: Bool {
        get { state.isWaitingForUser }
        set { state.isWaitingForUser = newValue }
    }

    var waitingReason: String {
        get { state.waitingReason }
        set { state.waitingReason = newValue }
    }

    var guardrailWarning: String? {
        get { state.guardrailWarning }
        set { state.guardrailWarning = newValue }
    }

    // MARK: - Dependencies

    private let browserState: BrowserState
    private let settings: AppSettings
    private let llmClient: AgentStreamingClient
    private let loopDetector = AgentLoopDetector()
    private var currentTaskHandle: Task<AgentResult, Never>?
    private weak var boundTab: Tab?
    private var tabClosureObserver: AnyCancellable?

    // MARK: - Configuration

    /// Maximum number of steps the agent can take before stopping
    var maxSteps: Int = 50

    /// Maximum wall-clock time (in seconds) for a task before stopping
    var taskTimeout: TimeInterval = 300

    /// The threshold (0.0-1.0) at which to show warnings (default 80%)
    private let warningThreshold: Double = 0.8

    /// Number of steps remaining before the limit is reached
    var stepsRemaining: Int {
        max(0, maxSteps - currentStepCount)
    }

    /// Current step count (tracked during execution)
    private(set) var currentStepCount: Int = 0

    // MARK: - Initialization

    init(browserState: BrowserState, settings: AppSettings) {
        self.browserState = browserState
        self.settings = settings
        self.llmClient = AgentStreamingClient(settings: settings)
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
        currentStepCount = 0
        loopDetector.reset()
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

                if !tabs.contains(where: { $0.id == boundId }) {
                    Log.Agent.warning("Bound tab was closed, cancelling agent")
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
            let prompt = AgentPromptBuilder.buildPrompt(task: task, snapshot: snapshot, previousSteps: steps)
            Log.Agent.debug("Sending prompt to LLM (length: \(prompt.count) chars)")
            let llmResponse = try await llmClient.callLLM(prompt: prompt, systemPrompt: AgentPromptBuilder.systemPrompt)
            Log.Agent.info("LLM Response:\n\(llmResponse)")

            // Parse thought and action
            guard let (thought, action) = AgentResponseParser.parseResponse(llmResponse) else {
                let failureCount = loopDetector.recordParseFailure()
                let maxFailures = loopDetector.maxConsecutiveParseFailures
                Log.Agent.warning("Parse failed (attempt \(failureCount)/\(maxFailures)). Raw response:\n\(llmResponse)")

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
            if case .click(let elementId) = action {
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
                    Log.Agent.warning("Stuck loop detected (\(loopType)) - attempting recovery \(attempt)/\(loopDetector.maxLoopRecoveryAttempts)")

                    // Surface loop status in UI
                    progress = "Agent appears stuck, attempting recovery..."
                    if let tab = boundTab {
                        tab.agentProgress = "Recovering from loop..."
                    }

                    if let tab = boundTab, tab.canGoBack {
                        let recoveryStep = AgentStep(type: .action, content: "Loop detected (\(loopType)), going back to try different approach", timestamp: Date())
                        steps.append(recoveryStep)

                        tab.goBack()
                        try await bridge.waitForLoad(timeout: 5.0)

                        loopDetector.clearActions()

                        let resultStep = AgentStep(type: .result, content: "Navigated back after loop detection", timestamp: Date())
                        steps.append(resultStep)

                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                }

                Log.Agent.warning("Stuck loop detected (\(loopType)) - forcing completion")
                let doneStep = AgentStep(type: .done, content: "Task ended: \(loopType)", timestamp: Date())
                steps.append(doneStep)
                return AgentResult(success: false, summary: "Agent got stuck: \(loopType)", steps: steps)
            }

            // 3. Act - Execute the action
            do {
                let result = try await executeAction(action, bridge: bridge)

                if case .done(let summary) = action {
                    Log.Agent.info("Task completed successfully: \(summary)")
                    let doneStep = AgentStep(type: .done, content: summary, timestamp: Date())
                    steps.append(doneStep)
                    return AgentResult(success: true, summary: summary, steps: steps)
                }

                let resultStep = AgentStep(type: .result, content: result, timestamp: Date())
                steps.append(resultStep)

                try await Task.sleep(nanoseconds: 500_000_000)

            } catch {
                let errorStep = AgentStep(type: .error, content: error.localizedDescription, timestamp: Date())
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
        case .click(let id):
            if let elements = elementById, let el = elements[id] {
                let label = el.text ?? el.ariaLabel ?? el.placeholder ?? el.tag
                return "Clicking '\(label)'"
            }
            return "Clicking element #\(id)"
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
            let validatedURL = try NavigationPolicy.validate(urlString)
            let tab = try requireBoundTab()
            tab.load(validatedURL.absoluteString)
            try await bridge.waitForLoad(timeout: 10.0)
            return "Navigated to \(validatedURL.absoluteString)"

        case .back:
            let tab = try requireBoundTab()
            guard tab.canGoBack else {
                return "Cannot go back - no history"
            }
            tab.goBack()
            try await bridge.waitForLoad(timeout: 5.0)
            loopDetector.clearActions()
            return "Navigated back to previous page"

        case .waitForUser(let reason):
            isWaitingForUser = true
            waitingReason = reason
            Log.Agent.info("Waiting for user action: \(reason)")

            let startURL = try? await bridge.snapshot().url
            for _ in 0..<60 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000_000)

                if let currentURL = try? await bridge.snapshot().url,
                   currentURL != startURL {
                    isWaitingForUser = false
                    waitingReason = ""
                    return "User completed action - page changed"
                }
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
}
