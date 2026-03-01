import Foundation
@testable import WheelBrowser

/// Evaluates whether an agent test scenario's success criteria were met
@MainActor
struct SuccessCriteriaEvaluator {

    /// Evaluate all criteria against the agent result and current page state
    /// Returns (passed, failureReasons, warnings)
    static func evaluate(
        criteria: SuccessCriteria,
        agentResult: AgentResult,
        bridge: (any BrowserBridge)?
    ) async -> (passed: Bool, failures: [String], warnings: [String]) {
        var failures: [String] = []
        var warnings: [String] = []

        // Check agent success
        if criteria.requireAgentSuccess && !agentResult.success {
            failures.append("Agent did not report success (done() not called). Summary: \(agentResult.summary)")
        }

        // Get final page state for URL/title/content checks
        let finalState: PageSnapshot?
        if let bridge = bridge {
            finalState = try? await bridge.snapshot()
        } else {
            finalState = nil
        }

        // Check URL
        if let urlContains = criteria.urlContains {
            if let snapshot = finalState {
                if !snapshot.url.lowercased().contains(urlContains.lowercased()) {
                    failures.append("URL '\(snapshot.url)' does not contain '\(urlContains)'")
                }
            } else {
                failures.append("Could not capture page state to check URL criteria")
            }
        }

        // Check title
        if let titleContains = criteria.titleContains {
            if let snapshot = finalState {
                if !snapshot.title.lowercased().contains(titleContains.lowercased()) {
                    failures.append("Title '\(snapshot.title)' does not contain '\(titleContains)'")
                }
            } else {
                failures.append("Could not capture page state to check title criteria")
            }
        }

        // Check page content
        if let pageContains = criteria.pageContains {
            if let snapshot = finalState {
                let contentText = snapshot.contentSummary ?? ""
                let elementsText = snapshot.elements.compactMap { $0.text }.joined(separator: " ")
                let headingsText = (snapshot.headings ?? []).map { $0.text }.joined(separator: " ")
                let allText = "\(contentText) \(elementsText) \(headingsText)"

                if !allText.lowercased().contains(pageContains.lowercased()) {
                    failures.append("Page content does not contain '\(pageContains)'")
                }
            } else {
                failures.append("Could not capture page state to check content criteria")
            }
        }

        // Check agent summary
        if let summaryContains = criteria.summaryContains {
            if !agentResult.summary.lowercased().contains(summaryContains.lowercased()) {
                failures.append("Agent summary '\(agentResult.summary)' does not contain '\(summaryContains)'")
            }
        }

        // Efficiency check (warning only, doesn't fail)
        if let maxExpectedSteps = criteria.maxExpectedSteps {
            let actionCount = agentResult.steps.filter { $0.type == .action }.count
            if actionCount > maxExpectedSteps {
                warnings.append("Took \(actionCount) actions (expected <= \(maxExpectedSteps))")
            }
        }

        return (passed: failures.isEmpty, failures: failures, warnings: warnings)
    }
}
