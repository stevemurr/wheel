import Testing
import Foundation
@testable import WheelBrowser

/// Live agent tests that run the full automation pipeline against real web pages
/// with real LLM calls. These tests verify end-to-end agent capability.
///
/// Run all live tests:
///   WHEEL_RUN_LIVE_AGENT_TESTS=1 swift test --filter AgentLiveTests
///
/// Run a specific scenario:
///   WHEEL_RUN_LIVE_AGENT_TESTS=1 swift test --filter AgentLiveTests/search_duckduckgo
///
/// Run scenarios by tag:
///   WHEEL_RUN_LIVE_AGENT_TESTS=1 swift test --filter AgentLiveTests/testByTag
@Suite("Agent Live Tests", .tags(.live))
struct AgentLiveTests {
    private static let liveTestsEnvironmentKey = "WHEEL_RUN_LIVE_AGENT_TESTS"

    private static var liveTestsEnabled: Bool {
        ProcessInfo.processInfo.environment[liveTestsEnvironmentKey] == "1"
    }

    /// Fixtures directory containing scenario JSON files
    private var fixturesDirectory: URL {
        AgentTestScenario.fixturesDirectory
    }

    // MARK: - Individual Scenario Tests

    @Test("search_duckduckgo", .tags(.search, .basic))
    @MainActor
    func searchDuckDuckGo() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "search_duckduckgo")
    }

    @Test("navigate_wikipedia", .tags(.navigation))
    @MainActor
    func navigateWikipedia() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "navigate_wikipedia")
    }

    @Test("direct_navigation", .tags(.navigation, .basic))
    @MainActor
    func directNavigation() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "direct_navigation")
    }

    @Test("read_content", .tags(.read))
    @MainActor
    func readContent() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "read_content")
    }

    @Test("multi_step_navigation", .tags(.navigation, .multiStep))
    @MainActor
    func multiStepNavigation() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "multi_step_navigation")
    }

    @Test("scroll_and_find", .tags(.scroll))
    @MainActor
    func scrollAndFind() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "scroll_and_find")
    }

    @Test("hn_arxiv_first_5_pages", .tags(.collection, .multiStep))
    @MainActor
    func hnArxivFirstFivePages() async throws {
        guard Self.liveTestsEnabled else { return }
        try await runScenario(named: "hn_arxiv_first_5_pages")
    }

    // MARK: - Full Suite

    @Test("Run all scenarios and generate report")
    @MainActor
    func runAllScenariosWithReport() async throws {
        guard Self.liveTestsEnabled else { return }
        let browserState = BrowserState()
        let settings = AppSettings.shared

        let results = await AgentTestRunner.runAll(
            from: fixturesDirectory,
            browserState: browserState,
            settings: settings
        )

        // Print the report
        let report = AgentTestReporter.report(results)
        print(report)

        // Save results for trend tracking
        let historyPath = resultsHistoryPath()
        try? AgentTestReporter.saveResults(results, to: historyPath)
        print("\nResults saved to: \(historyPath)")

        // Assert
        let failures = results.filter { !$0.passed }
        #expect(failures.isEmpty, "Failed scenarios: \(failures.map(\.scenarioName).joined(separator: ", "))")
    }

    // MARK: - Helpers

    @MainActor
    private func runScenario(named name: String) async throws {
        let scenario = try AgentTestScenario.load(named: name, from: fixturesDirectory)
        let browserState = BrowserState()
        let settings = AppSettings.shared

        let result = await AgentTestRunner.run(
            scenario,
            browserState: browserState,
            settings: settings
        )

        // Print individual result
        let report = AgentTestReporter.report([result])
        print(report)

        // Assert
        if !result.passed {
            let reasons = result.failureReasons.joined(separator: "; ")
            Issue.record("Scenario '\(name)' failed: \(reasons)")
        }
    }

    private func resultsHistoryPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("WheelBrowser")

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        return appSupport.appendingPathComponent("agent_test_results.json").path
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var live: Self
    @Tag static var search: Self
    @Tag static var navigation: Self
    @Tag static var basic: Self
    @Tag static var read: Self
    @Tag static var multiStep: Self
    @Tag static var scroll: Self
    @Tag static var collection: Self
}
