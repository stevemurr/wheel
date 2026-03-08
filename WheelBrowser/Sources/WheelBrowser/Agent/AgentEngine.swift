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

private extension AgentAction {
    var analyticsTag: String {
        switch self {
        case .click:
            return "click"
        case .type:
            return "type"
        case .pressEnter:
            return "press_enter"
        case .scroll:
            return "scroll"
        case .navigate:
            return "navigate"
        case .back:
            return "back"
        case .waitForUser:
            return "wait_for_user"
        case .wait:
            return "wait"
        case .readText:
            return "read_text"
        case .newTab:
            return "new_tab"
        case .openTab:
            return "open_tab"
        case .switchTab:
            return "switch_tab"
        case .extractContent:
            return "extract_content"
        case .readLinks:
            return "read_links"
        case .collectLinks:
            return "collect_links"
        case .advancePagination:
            return "advance_pagination"
        case .done:
            return "done"
        }
    }
}

/// The result of an agent task
struct AgentResult {
    let success: Bool
    let summary: String
    let steps: [AgentStep]
    let artifacts: [ChatArtifact]
    let collection: AgentCollectionSummary?
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
    case collectLinks
    case advancePagination(url: String?)
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
    private(set) var lastResult: AgentResult?

    // MARK: - Dependencies (excluded from observation)

    @ObservationIgnored private let browserState: BrowserState
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let contextService: any WheelModelContextServing
    @ObservationIgnored private let bridgeProvider: any BrowserBridgeProvider
    @ObservationIgnored private let loopDetector = AgentLoopDetector()
    @ObservationIgnored private var currentTaskHandle: Task<AgentResult, Never>?
    @ObservationIgnored private weak var boundTab: Tab?
    @ObservationIgnored private var tabClosureObserverTask: Task<Void, Never>?
    @ObservationIgnored private var currentRunID: UUID?
    @ObservationIgnored private var currentThreadID: String?
    @ObservationIgnored private var taskIntent = AgentTaskIntent(
        seedURL: nil,
        sourceHosts: [],
        targetHosts: [],
        pageLimit: nil,
        requiresUniqueURLs: true,
        collectionMode: .none,
        canonicalizationStrategy: .none
    )
    @ObservationIgnored private var collectionAccumulator = AgentCollectionAccumulator()
    @ObservationIgnored private var crawlSession: AgentCrawlSession?
    @ObservationIgnored private var lastCollectionDelta: CollectionDelta?

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
        self.contextService = WheelModelContextService.shared
        self.bridgeProvider = browserState
    }

    /// Test initializer allowing injection of mock dependencies
    init(
        browserState: BrowserState,
        contextService: any WheelModelContextServing,
        bridgeProvider: any BrowserBridgeProvider
    ) {
        self.browserState = browserState
        self.settings = AppSettings.shared
        self.contextService = contextService
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
            return AgentResult(success: false, summary: "Agent is already running", steps: [], artifacts: [], collection: nil)
        }

        guard let activeTab = browserState.activeTab else {
            return AgentResult(success: false, summary: "No active tab", steps: [], artifacts: [], collection: nil)
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
        taskIntent = AgentTaskIntent.parse(task: task)
        collectionAccumulator = AgentCollectionAccumulator()
        crawlSession = taskIntent.isLinkCollection ? AgentCrawlSession(intent: taskIntent) : nil
        lastCollectionDelta = nil
        lastResult = nil
        currentRunID = UUID()

        let taskHandle = Task { () -> AgentResult in
            defer { self.resetState() }
            do {
                let result = try await executeTask(task)
                await MainActor.run {
                    self.lastResult = result
                }
                return result
            } catch {
                Log.Agent.error("Task failed with error: \(error.localizedDescription)")
                let errorStep = AgentStep(type: .error, content: error.localizedDescription, timestamp: Date())
                let failureResult = AgentResult(
                    success: false,
                    summary: error.localizedDescription,
                    steps: self.steps + [errorStep],
                    artifacts: self.currentArtifacts(),
                    collection: self.currentCollectionSummary()
                )
                await MainActor.run {
                    self.steps.append(errorStep)
                    self.error = error.localizedDescription
                    self.lastResult = failureResult
                }
                return failureResult
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

    func clearHistory() {
        steps = []
        currentTask = ""
        error = nil
        guardrailWarning = nil
        streamingThought = nil
        lastResult = nil
    }

    // MARK: - State Management

    /// Atomically reset all mutable state after a task completes
    private func resetState() {
        if let threadID = currentThreadID {
            Task {
                try? await contextService.resetThread(threadID: threadID)
            }
        }
        cleanupTabBinding()
        isRunning = false
        guardrailWarning = nil
        streamingThought = nil
        currentStepCount = 0
        currentRunID = nil
        currentThreadID = nil
        taskIntent = AgentTaskIntent(
            seedURL: nil,
            sourceHosts: [],
            targetHosts: [],
            pageLimit: nil,
            requiresUniqueURLs: true,
            collectionMode: .none,
            canonicalizationStrategy: .none
        )
        collectionAccumulator = AgentCollectionAccumulator()
        crawlSession = nil
        lastCollectionDelta = nil
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
    private func callLLMWithStreaming(prompt: String) async throws -> GeneratedAgentDecision {
        guard let threadID = currentThreadID else {
            throw AgentError.invalidLLMResponse("Agent LM context thread was not initialized")
        }

        defer { streamingThought = nil }

        let stream = try await contextService.streamAgentDecision(
            prompt: prompt,
            threadID: threadID
        )
        var completedResponse: LMManagedStructuredResponse<GeneratedAgentDecision>?

        for try await event in stream {
            switch event {
            case .partialThought(let thought):
                streamingThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
            case .completed(let response):
                completedResponse = response
            }
        }

        guard let completedResponse else {
            throw AgentError.invalidLLMResponse("Empty streaming response")
        }

        return completedResponse.content
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

        guard let runID = currentRunID else {
            throw AgentError.invalidLLMResponse("Agent run ID was not initialized")
        }

        currentThreadID = try await contextService.openAgentThread(
            tabId: tabId,
            runId: runID,
            instructions: AgentPromptBuilder.threadInstructions
        )

        if let bridge = bridgeProvider.bridge(for: tabId) {
            try await navigateToSeedPageIfNeeded(bridge: bridge)
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

            let observation = try await bridge.snapshot(request: taskIntent.snapshotRequest)
            crawlSession?.observePage(url: observation.url, paginationCandidates: observation.paginationCandidates)

            // Track URL for progress detection
            loopDetector.recordURL(observation.url)

            let observationStep = AgentStep(
                type: .observation,
                content: observation.textRepresentation,
                timestamp: Date()
            )
            steps.append(observationStep)

            try await ensureObservedPageCollection(observation: observation, bridge: bridge)

            if let autoCompletionSummary = collectionAutoCompletionSummary() {
                Log.Agent.info("Collection completed automatically: \(autoCompletionSummary)")
                let doneStep = AgentStep(type: .done, content: autoCompletionSummary, timestamp: Date())
                steps.append(doneStep)
                return buildResult(success: true, summary: autoCompletionSummary)
            }

            // 2. Think - Ask LLM for next action
            let recentErrors = steps.suffix(6).filter { $0.type == .error }.count
            let runtimeStatus = AgentRuntimeStatus(
                iteration: iteration,
                maxSteps: maxSteps,
                recentErrorCount: recentErrors,
                guardrailWarning: guardrailWarning,
                pageProgress: collectionProgressNote()
            )
            let prompt = AgentPromptBuilder.buildPrompt(
                task: task,
                intent: taskIntent,
                observation: observation,
                runtimeStatus: runtimeStatus,
                accumulatorSummary: taskIntent.isLinkCollection ? collectionAccumulator.summaryText() : nil
            )
            Log.Agent.debug("Sending prompt to LLM (length: \(prompt.count) chars)")
            let llmDecision = try await callLLMWithStreaming(prompt: prompt)

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
                await appendAgentExternalTurn(
                    text: errorStep.content,
                    tags: ["parse-error", "retry"]
                )
                continue
            }

            loopDetector.resetParseFailures()
            Log.Agent.info("Parsed - Thought: \(thought), Action: \(String(describing: action))")

            let thoughtStep = AgentStep(type: .thought, content: thought, timestamp: Date())
            steps.append(thoughtStep)

            // Build element ID map for O(1) lookup (needed for descriptive action labels and loop detection)
            let elementById = Dictionary(uniqueKeysWithValues: observation.interactiveElements.map { ($0.id, $0) })

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
                        await appendAgentExternalTurn(
                            text: resultStep.content,
                            tags: ["loop-recovery", "back"]
                        )

                        try await Task.sleep(nanoseconds: 300_000_000)
                        continue

                    case .scrollDown:
                        let recoveryStep = AgentStep(type: .action, content: "Loop detected (\(loopType)), scrolling down to find new elements", timestamp: Date())
                        steps.append(recoveryStep)

                        try await bridge.scroll(deltaY: 400)
                        loopDetector.clearActions()

                        let resultStep = AgentStep(type: .result, content: "Scrolled down after loop detection to reveal new elements", timestamp: Date())
                        steps.append(resultStep)
                        await appendAgentExternalTurn(
                            text: resultStep.content,
                            tags: ["loop-recovery", "scroll"]
                        )

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
                return buildResult(
                    success: false,
                    summary: "Agent got stuck: \(loopType)"
                )
            }

            // 3. Act - Execute the action
            do {
                let actionResult = try await executeAction(action, bridge: bridge, elementById: elementById)

                if case .done(let summary) = action {
                    if let rejection = verifyCollectionDoneCondition() {
                        doneRejections += 1
                        Log.Agent.warning("done() rejected (\(doneRejections)/\(maxDoneRejections)): \(rejection)")
                        let correctionStep = AgentStep(type: .error, content: "Verification failed: \(rejection) Do NOT call done() again immediately. Instead, take a corrective action (collect_links, advance_pagination, navigate, scroll, click, or try a different approach). If the task truly cannot be completed, call done(\"Unable to complete: \(rejection)\").", timestamp: Date())
                        steps.append(correctionStep)
                        await appendAgentExternalTurn(
                            text: correctionStep.content,
                            tags: ["verification-error"]
                        )
                        continue
                    }

                    // Post-done() verification
                    if doneRejections < maxDoneRejections {
                        if let rejection = await verifyDoneCondition(bridge: bridge) {
                            doneRejections += 1
                            Log.Agent.warning("done() rejected (\(doneRejections)/\(maxDoneRejections)): \(rejection)")
                            let correctionStep = AgentStep(type: .error, content: "Verification failed: \(rejection) Do NOT call done() again immediately. Instead, take a corrective action (navigate, scroll, click, or try a different approach). If the task truly cannot be completed, call done(\"Unable to complete: \(rejection)\").", timestamp: Date())
                            steps.append(correctionStep)
                            await appendAgentExternalTurn(
                                text: correctionStep.content,
                                tags: ["verification-error"]
                            )
                            continue
                        }
                    }

                    let completionSummary = completionSummary(for: summary)
                    Log.Agent.info("Task completed successfully: \(completionSummary)")
                    let doneStep = AgentStep(type: .done, content: completionSummary, timestamp: Date())
                    steps.append(doneStep)
                    return buildResult(success: true, summary: completionSummary)
                }

                let resultStep = AgentStep(type: .result, content: actionResult.message, timestamp: Date())
                steps.append(resultStep)
                await appendAgentExternalTurn(
                    text: actionResult.message,
                    tags: ["action-result", action.analyticsTag]
                )

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
                await appendAgentExternalTurn(
                    text: mappedMessage,
                    tags: ["action-error", action.analyticsTag]
                )
            }
        }

        Log.Agent.error("Max steps (\(self.maxSteps)) reached without completion")
        let errorStep = AgentStep(type: .error, content: "Task stopped: reached maximum of \(maxSteps) steps", timestamp: Date())
        steps.append(errorStep)
        throw AgentError.maxIterationsReached
    }

    private func collectionProgressNote() -> String? {
        guard taskIntent.isLinkCollection else {
            return nil
        }

        var parts: [String] = []

        if let crawlSession {
            if let pageLimit = crawlSession.pageLimit {
                parts.append("Pages scanned: \(crawlSession.pagesScanned)/\(pageLimit).")
            } else {
                parts.append("Pages scanned: \(crawlSession.pagesScanned).")
            }
            parts.append(crawlSession.hasAvailablePaginationCandidate
                ? "Next page available."
                : "No unseen pagination target available.")
        }
        parts.append("Collected \(collectionAccumulator.totalUniqueCount) unique links so far.")
        if let lastCollectionDelta {
            parts.append("Last collect: \(lastCollectionDelta.added.count) new, \(lastCollectionDelta.duplicateCount) duplicates.")
        }
        if !taskIntent.targetHosts.isEmpty {
            parts.append("Target host filter: \(taskIntent.targetHosts.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    private func currentArtifacts() -> [ChatArtifact] {
        guard taskIntent.isLinkCollection,
              crawlSession?.hasMaterializedCollectionResult == true else {
            return []
        }

        let title = taskIntent.targetHosts.first ?? "Collected"
        return collectionAccumulator.artifacts(title: title)
    }

    private func currentCollectionSummary() -> AgentCollectionSummary? {
        guard taskIntent.isLinkCollection,
              let crawlSession,
              crawlSession.hasMaterializedCollectionResult else {
            return nil
        }

        return AgentCollectionSummary(
            pagesScanned: crawlSession.pagesScanned,
            pageLimit: taskIntent.pageLimit,
            sourceHosts: taskIntent.sourceHosts,
            targetHosts: taskIntent.targetHosts,
            totalUniqueCount: collectionAccumulator.totalUniqueCount,
            items: collectionAccumulator.sortedMatches
        )
    }

    private func buildResult(success: Bool, summary: String) -> AgentResult {
        AgentResult(
            success: success,
            summary: summary,
            steps: steps,
            artifacts: currentArtifacts(),
            collection: currentCollectionSummary()
        )
    }

    private func collectionAutoCompletionSummary() -> String? {
        guard taskIntent.isLinkCollection,
              let crawlSession,
              crawlSession.hasMaterializedCollectionResult else {
            return nil
        }

        let total = collectionAccumulator.totalUniqueCount
        if crawlSession.pageBudgetReached {
            if total == 1 {
                return "Collected 1 unique link from \(crawlSession.pagesScanned) requested pages."
            }
            return "Collected \(total) unique links from \(crawlSession.pagesScanned) requested pages."
        }

        if let pageLimit = crawlSession.pageLimit,
           crawlSession.pagesScanned > 0,
           !crawlSession.hasAvailablePaginationCandidate {
            if total == 1 {
                return "Collected 1 unique link after scanning \(crawlSession.pagesScanned) of \(pageLimit) requested pages because no additional pagination targets were available."
            }
            return "Collected \(total) unique links after scanning \(crawlSession.pagesScanned) of \(pageLimit) requested pages because no additional pagination targets were available."
        }

        return nil
    }

    private func completionSummary(for requestedSummary: String) -> String {
        guard let crawlSession,
              let pageLimit = crawlSession.pageLimit,
              crawlSession.pagesScanned < pageLimit,
              !crawlSession.hasAvailablePaginationCandidate else {
            return requestedSummary
        }

        let normalizedSummary = requestedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = " Scanned \(crawlSession.pagesScanned) of \(pageLimit) requested pages because no additional pagination targets were available."
        if normalizedSummary.isEmpty {
            return "Collection completed.\(suffix)"
        }
        if normalizedSummary.contains("Scanned \(crawlSession.pagesScanned) of \(pageLimit)") {
            return normalizedSummary
        }
        return normalizedSummary + suffix
    }

    private func verifyCollectionDoneCondition() -> String? {
        guard taskIntent.isLinkCollection, let crawlSession else {
            return nil
        }

        guard crawlSession.hasMaterializedCollectionResult else {
            return "No collection result has been materialized yet. Use collect_links before finishing."
        }

        if let pageLimit = crawlSession.pageLimit,
           crawlSession.pagesScanned < pageLimit,
           crawlSession.hasAvailablePaginationCandidate {
            return "You have only scanned \(crawlSession.pagesScanned) of \(pageLimit) requested pages and another page is available."
        }

        return nil
    }

    private func ensureObservedPageCollection(
        observation: ReducedPageObservation,
        bridge: any BrowserBridge
    ) async throws {
        guard taskIntent.isLinkCollection,
              var crawlSession,
              crawlSession.shouldCollectPage(url: observation.url) else {
            return
        }

        let request = taskIntent.linkCollectionRequest ?? LinkCollectionRequest(
            targetHosts: taskIntent.targetHosts,
            includePaginationLinks: true,
            maxMatches: 250,
            canonicalizationStrategy: taskIntent.canonicalizationStrategy
        )

        let actionStep = AgentStep(
            type: .action,
            content: "Collecting matching links from the current crawl page",
            timestamp: Date()
        )
        steps.append(actionStep)

        let result = try await bridge.collectLinks(request)
        let pageIndex = max(1, crawlSession.currentPageIndex)
        let delta = collectionAccumulator.absorb(result.withPageIndex(pageIndex))
        crawlSession.markCollectedPage(url: observation.url)
        self.crawlSession = crawlSession
        lastCollectionDelta = delta

        let message: String
        if delta.added.isEmpty && delta.duplicateCount == 0 {
            message = "No matching links found on this page. Scanned \(result.totalLinksScanned) links."
        } else {
            message = "Collected links from this page: \(delta.message)"
        }

        let resultStep = AgentStep(type: .result, content: message, timestamp: Date())
        steps.append(resultStep)
        await appendAgentExternalTurn(
            text: message,
            tags: ["auto-collection", "collect_links"]
        )
    }

    private func navigateToSeedPageIfNeeded(bridge: any BrowserBridge) async throws {
        guard let seedURL = taskIntent.seedURL,
              !taskIntent.sourceHosts.isEmpty else {
            return
        }

        let currentHost = boundTab?.url?.normalizedAgentHost ?? ""
        guard !taskIntent.sourceHosts.contains(currentHost) else {
            return
        }

        let preState = await bridge.capturePreActionState()
        let validatedURL = try NavigationPolicy.validate(seedURL)
        let tab = try requireBoundTab()

        let actionStep = AgentStep(type: .action, content: "Navigating to source page \(validatedURL.absoluteString)", timestamp: Date())
        steps.append(actionStep)
        tab.load(validatedURL.absoluteString)
        try await bridge.waitForLoad(timeout: 10.0)
        let delta = await bridge.quickDelta(before: preState)
        let resultStep = AgentStep(type: .result, content: "Loaded source page. \(delta.description)", timestamp: Date())
        steps.append(resultStep)
        await appendAgentExternalTurn(text: resultStep.content, tags: ["seed-navigation"])
    }

    private func appendAgentExternalTurn(text: String, tags: [String]) async {
        guard let threadID = currentThreadID else {
            return
        }

        guard let state = try? await contextService.threadState(threadID: threadID) else {
            return
        }

        let turn = LMNormalizedTurn(
            role: .tool,
            text: text,
            priority: 700,
            tags: tags,
            windowIndex: state.activeWindowIndex
        )

        try? await contextService.appendAgentTurns([turn], threadID: threadID)
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
        case .collectLinks:
            return "Collecting matching links from the page"
        case .advancePagination(let url):
            if let url, let host = URL(string: url)?.host {
                return "Advancing pagination to \(host)"
            }
            return "Advancing to the next page"
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
                if text.count > 1200 {
                    text = String(text.prefix(1200)) + "... (truncated)"
                }
                return ActionResult(
                    message: "Page content preview (\(pageContext.title)):\n\(text)",
                    delta: nil
                )
            }
            return ActionResult(message: "Could not extract page content.", delta: nil)

        case .readLinks:
            let links = try await bridge.getPageLinks()
            if links.isEmpty {
                return ActionResult(message: "No links found on this page.", delta: nil)
            }
            var lines = links.split(separator: "\n").map(String.init)
            let total = lines.count
            if lines.count > 10 {
                lines = Array(lines.prefix(10))
            }
            let preview = lines.joined(separator: "\n")
            let suffix = total > lines.count ? "\n... (\(total - lines.count) more links omitted)" : ""
            return ActionResult(
                message: "Links on page (sample):\n\(preview)\(suffix)",
                delta: nil
            )

        case .collectLinks:
            if var crawlSession = crawlSession,
               !crawlSession.shouldCollectPage(url: preState.url) {
                crawlSession.markCollectionMaterialized()
                self.crawlSession = crawlSession
                return ActionResult(
                    message: "The current crawl page has already been collected. \(collectionAccumulator.totalUniqueCount) unique links are in the result set.",
                    delta: nil
                )
            }

            let request = taskIntent.linkCollectionRequest ?? LinkCollectionRequest(
                targetHosts: taskIntent.targetHosts,
                includePaginationLinks: true,
                maxMatches: 250,
                canonicalizationStrategy: taskIntent.canonicalizationStrategy
            )
            let result = try await bridge.collectLinks(request)
            let pageIndex = max(1, crawlSession?.currentPageIndex ?? 1)
            let delta = collectionAccumulator.absorb(result.withPageIndex(pageIndex))
            crawlSession?.markCollectedPage(url: result.pageURL.isEmpty ? preState.url : result.pageURL)
            lastCollectionDelta = delta
            if delta.added.isEmpty && delta.duplicateCount == 0 {
                return ActionResult(
                    message: "No matching links found on this page. Scanned \(result.totalLinksScanned) links.",
                    delta: nil
                )
            }
            return ActionResult(
                message: "Collected links from this page: \(delta.message)",
                delta: nil
            )

        case .advancePagination(let requestedURL):
            guard var crawlSession else {
                return ActionResult(message: "No active crawl session. Navigate directly instead.", delta: nil)
            }

            if crawlSession.pageBudgetReached {
                self.crawlSession = crawlSession
                return ActionResult(
                    message: "The requested page budget has already been reached. Finish the task instead of advancing further.",
                    delta: nil
                )
            }

            guard let candidate = crawlSession.resolvePaginationCandidate(preferredURL: requestedURL) else {
                self.crawlSession = crawlSession
                return ActionResult(message: "No unseen pagination target remains on this page.", delta: nil)
            }

            guard crawlSession.registerPaginationVisit(candidate) else {
                self.crawlSession = crawlSession
                return ActionResult(message: "Pagination target was already visited: \(candidate.url)", delta: nil)
            }

            self.crawlSession = crawlSession

            let validatedURL = try NavigationPolicy.validate(candidate.url)
            let tab = try requireBoundTab()
            tab.load(validatedURL.absoluteString)
            try await bridge.waitForLoad(timeout: 10.0)
            let delta = await bridge.quickDelta(before: preState)
            let label = candidate.text.isEmpty ? validatedURL.absoluteString : candidate.text
            return ActionResult(message: "Advanced pagination via \(label). \(delta.description)", delta: delta)

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
