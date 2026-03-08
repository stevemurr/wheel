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

        if let collectionCountAtLeast = criteria.collectionCountAtLeast {
            let total = agentResult.collection?.totalUniqueCount ?? 0
            if total < collectionCountAtLeast {
                failures.append("Collected \(total) items, expected at least \(collectionCountAtLeast)")
            }
        }

        if let expectedHost = criteria.collectionHost {
            guard let items = agentResult.collection?.items, !items.isEmpty else {
                failures.append("No collection items were available to validate host '\(expectedHost)'")
                applyEfficiencyWarnings(&warnings, criteria: criteria, agentResult: agentResult)
                return (passed: failures.isEmpty, failures: failures, warnings: warnings)
            }

            let mismatches = items.filter {
                URL(string: $0.canonicalURL)?.normalizedAgentHost != expectedHost
            }
            if !mismatches.isEmpty {
                failures.append("Collected items included hosts other than '\(expectedHost)'")
            }
        }

        if let expectedPagesScanned = criteria.pagesScanned {
            let actualPagesScanned = agentResult.collection?.pagesScanned ?? 0
            if actualPagesScanned != expectedPagesScanned {
                failures.append("Pages scanned was \(actualPagesScanned), expected \(expectedPagesScanned)")
            }
        }

        if let artifactPresent = criteria.artifactPresent {
            let hasArtifacts = !agentResult.artifacts.isEmpty
            if artifactPresent != hasArtifacts {
                failures.append("Artifact presence was \(hasArtifacts), expected \(artifactPresent)")
            }
        }

        if criteria.noDuplicateCanonicalIDs == true,
           let items = agentResult.collection?.items {
            let canonicalIDs = items.compactMap(\.canonicalID)
            if canonicalIDs.count != Set(canonicalIDs).count {
                failures.append("Collection contained duplicate canonical IDs")
            }
        }

        applyEfficiencyWarnings(&warnings, criteria: criteria, agentResult: agentResult)
        return (passed: failures.isEmpty, failures: failures, warnings: warnings)
    }

    private static func applyEfficiencyWarnings(
        _ warnings: inout [String],
        criteria: SuccessCriteria,
        agentResult: AgentResult
    ) {
        if let maxExpectedSteps = criteria.maxExpectedSteps {
            let actionCount = agentResult.steps.filter { $0.type == .action }.count
            if actionCount > maxExpectedSteps {
                warnings.append("Took \(actionCount) actions (expected <= \(maxExpectedSteps))")
            }
        }
    }
}
