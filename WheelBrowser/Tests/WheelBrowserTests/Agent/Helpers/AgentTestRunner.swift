import Foundation
@testable import WheelBrowser

/// Result of running a single agent test scenario
struct AgentTestResult: Sendable {
    let scenarioName: String
    let scenarioDescription: String
    let passed: Bool
    let agentSuccess: Bool
    let agentSummary: String
    let finalURL: String
    let finalTitle: String
    let stepCount: Int
    let actionCount: Int
    let duration: TimeInterval
    let failureReasons: [String]
    let warnings: [String]
    let tags: [String]
}

/// Orchestrates running a live agent test scenario
@MainActor
struct AgentTestRunner {

    /// Run a single scenario with live LLM and real browser
    static func run(
        _ scenario: AgentTestScenario,
        browserState: BrowserState,
        settings: AppSettings
    ) async -> AgentTestResult {
        let startTime = Date()

        // 1. Navigate the active tab to startURL
        guard let activeTab = browserState.activeTab else {
            return failResult(scenario: scenario, reason: "No active tab available", startTime: startTime)
        }

        activeTab.load(scenario.startURL)

        // 2. Wait for page to load
        if let bridge = browserState.bridge(for: activeTab.id) {
            try? await bridge.waitForLoad(timeout: 10.0, stableThreshold: 1.0)
        } else {
            // Small delay fallback if bridge unavailable
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        // 3. Create and configure AgentEngine
        let engine = AgentEngine(browserState: browserState, settings: settings)
        if let maxSteps = scenario.maxSteps {
            engine.maxSteps = maxSteps
        }
        if let timeout = scenario.timeout {
            engine.taskTimeout = timeout
        }

        // 4. Run the agent
        let agentResult = await engine.run(task: scenario.task)

        let duration = Date().timeIntervalSince(startTime)

        // 5. Get final page state
        let bridge = browserState.bridge(for: activeTab.id)
        let finalSnapshot = try? await bridge?.snapshot()

        // 6. Evaluate success criteria
        let (passed, failures, warnings) = await SuccessCriteriaEvaluator.evaluate(
            criteria: scenario.successCriteria,
            agentResult: agentResult,
            bridge: bridge
        )

        let actionCount = agentResult.steps.filter { $0.type == .action }.count

        return AgentTestResult(
            scenarioName: scenario.name,
            scenarioDescription: scenario.description,
            passed: passed,
            agentSuccess: agentResult.success,
            agentSummary: agentResult.summary,
            finalURL: finalSnapshot?.url ?? activeTab.url?.absoluteString ?? "unknown",
            finalTitle: finalSnapshot?.title ?? activeTab.title,
            stepCount: agentResult.steps.count,
            actionCount: actionCount,
            duration: duration,
            failureReasons: failures,
            warnings: warnings,
            tags: scenario.tags ?? []
        )
    }

    /// Run all scenarios from a directory
    static func runAll(
        from directory: URL,
        browserState: BrowserState,
        settings: AppSettings,
        tags: [String]? = nil
    ) async -> [AgentTestResult] {
        guard let scenarios = try? AgentTestScenario.loadAll(from: directory) else {
            return []
        }

        let filtered: [AgentTestScenario]
        if let tags = tags {
            filtered = scenarios.filter { scenario in
                guard let scenarioTags = scenario.tags else { return false }
                return !Set(tags).isDisjoint(with: Set(scenarioTags))
            }
        } else {
            filtered = scenarios
        }

        var results: [AgentTestResult] = []
        for scenario in filtered {
            let result = await run(scenario, browserState: browserState, settings: settings)
            results.append(result)
        }
        return results
    }

    // MARK: - Private

    private static func failResult(scenario: AgentTestScenario, reason: String, startTime: Date) -> AgentTestResult {
        AgentTestResult(
            scenarioName: scenario.name,
            scenarioDescription: scenario.description,
            passed: false,
            agentSuccess: false,
            agentSummary: reason,
            finalURL: "",
            finalTitle: "",
            stepCount: 0,
            actionCount: 0,
            duration: Date().timeIntervalSince(startTime),
            failureReasons: [reason],
            warnings: [],
            tags: scenario.tags ?? []
        )
    }
}
