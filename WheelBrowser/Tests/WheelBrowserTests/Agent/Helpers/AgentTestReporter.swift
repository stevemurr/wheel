import Foundation

/// Formats and persists agent test results for capability tracking
struct AgentTestReporter {

    /// Generate a human-readable report from test results
    static func report(_ results: [AgentTestResult]) -> String {
        guard !results.isEmpty else { return "No test results." }

        var lines: [String] = []
        let passed = results.filter { $0.passed }.count
        let failed = results.count - passed
        let totalDuration = results.reduce(0.0) { $0 + $1.duration }
        let avgSteps = results.reduce(0) { $0 + $1.actionCount } / results.count

        lines.append("=" .repeated(60))
        lines.append("AGENT TEST RESULTS")
        lines.append("=" .repeated(60))
        lines.append("")
        lines.append("Summary: \(passed)/\(results.count) passed, \(failed) failed")
        lines.append("Total duration: \(String(format: "%.1f", totalDuration))s")
        lines.append("Avg actions per scenario: \(avgSteps)")
        lines.append("")
        lines.append("-" .repeated(60))

        for result in results {
            let status = result.passed ? "PASS" : "FAIL"
            let statusIcon = result.passed ? "[+]" : "[-]"
            lines.append("")
            lines.append("\(statusIcon) \(result.scenarioName) — \(status)")
            lines.append("    \(result.scenarioDescription)")
            lines.append("    Duration: \(String(format: "%.1f", result.duration))s | Actions: \(result.actionCount) | Steps: \(result.stepCount)")
            lines.append("    Final URL: \(result.finalURL)")

            if result.agentSuccess {
                lines.append("    Agent: done() — \(result.agentSummary)")
            } else {
                lines.append("    Agent: FAILED — \(result.agentSummary)")
            }

            for failure in result.failureReasons {
                lines.append("    FAILURE: \(failure)")
            }
            for warning in result.warnings {
                lines.append("    WARNING: \(warning)")
            }
        }

        lines.append("")
        lines.append("=" .repeated(60))

        return lines.joined(separator: "\n")
    }

    /// Save results as JSON for trend tracking over time
    static func saveResults(_ results: [AgentTestResult], to path: String) throws {
        let entry = TestRunEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            results: results.map { result in
                TestRunEntry.ScenarioResult(
                    name: result.scenarioName,
                    passed: result.passed,
                    agentSuccess: result.agentSuccess,
                    actionCount: result.actionCount,
                    duration: result.duration,
                    failureReasons: result.failureReasons,
                    warnings: result.warnings
                )
            }
        )

        let fileURL = URL(fileURLWithPath: path)
        var history: [TestRunEntry] = []

        // Load existing history if file exists
        if FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONDecoder().decode([TestRunEntry].self, from: data) {
            history = existing
        }

        history.append(entry)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: fileURL)
    }
}

/// A single test run entry for history tracking
struct TestRunEntry: Codable {
    let timestamp: String
    let results: [ScenarioResult]

    struct ScenarioResult: Codable {
        let name: String
        let passed: Bool
        let agentSuccess: Bool
        let actionCount: Int
        let duration: TimeInterval
        let failureReasons: [String]
        let warnings: [String]
    }
}

// MARK: - String Helpers

private extension String {
    func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
