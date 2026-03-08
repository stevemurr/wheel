import Foundation

/// Represents a normalized action for loop detection (ignores element ID specifics).
struct NormalizedAction: Hashable {
    let type: String   // "click", "type", "scroll", etc.
    let target: String // Normalized target info (element text/role, not ID)

    init(from action: AgentAction, elementDescription: String? = nil) {
        switch action {
        case .click:
            self.type = "click"
            self.target = elementDescription ?? "unknown"
        case .type(_, let text):
            self.type = "type"
            self.target = text
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
        case .readText:
            self.type = "readText"
            self.target = ""
        case .newTab:
            self.type = "newTab"
            self.target = ""
        case .openTab(let url):
            self.type = "openTab"
            self.target = url
        case .switchTab(let index):
            self.type = "switchTab"
            self.target = String(index)
        case .extractContent:
            self.type = "extractContent"
            self.target = ""
        case .readLinks:
            self.type = "readLinks"
            self.target = ""
        case .collectLinks:
            self.type = "collectLinks"
            self.target = ""
        }
    }
}

/// Suggested recovery strategy when a loop is detected
enum LoopRecoveryStrategy {
    case goBack
    case scrollDown
    case admitFailure(reason: String)
}

/// Agent-specific loop detector that tracks NormalizedAction history,
/// URL-based progress, and detects various stuck patterns.
final class AgentLoopDetector {
    /// History of recent actions for semantic loop detection
    private(set) var recentActions: [NormalizedAction] = []
    /// Track consecutive parse failures for backoff
    private(set) var consecutiveParseFailures: Int = 0
    /// Track loop recovery attempts
    private(set) var loopRecoveryAttempts: Int = 0
    /// Track visited URLs for progress detection
    private(set) var visitedURLs: [String] = []

    let maxConsecutiveParseFailures = 3
    let maxLoopRecoveryAttempts = 2

    /// Record a new normalized action
    func recordAction(_ action: NormalizedAction) {
        recentActions.append(action)
        // Keep only last 10 actions for pattern detection
        if recentActions.count > 10 {
            recentActions.removeFirst()
        }
    }

    /// Record a URL visit for progress tracking
    func recordURL(_ url: String) {
        // Normalize by stripping fragments
        let normalized = url.components(separatedBy: "#").first ?? url
        if visitedURLs.last != normalized {
            visitedURLs.append(normalized)
        }
    }

    /// Check if the agent has been visiting new URLs (making progress)
    var isVisitingNewURLs: Bool {
        guard visitedURLs.count >= 3 else { return false }
        let recentURLs = visitedURLs.suffix(3)
        return Set(recentURLs).count >= 2
    }

    /// Record a parse failure and return the current count
    func recordParseFailure() -> Int {
        consecutiveParseFailures += 1
        return consecutiveParseFailures
    }

    /// Reset parse failure counter (called on successful parse)
    func resetParseFailures() {
        consecutiveParseFailures = 0
    }

    /// Record a loop recovery attempt and return the current count
    func recordRecoveryAttempt() -> Int {
        loopRecoveryAttempts += 1
        return loopRecoveryAttempts
    }

    /// Clear recent actions (e.g. after navigating back)
    func clearActions() {
        recentActions.removeAll()
    }

    /// Reset all state
    func reset() {
        recentActions.removeAll()
        consecutiveParseFailures = 0
        loopRecoveryAttempts = 0
        visitedURLs.removeAll()
    }

    /// Suggest a recovery strategy based on the detected loop type
    func suggestRecovery(loopType: String, canGoBack: Bool) -> LoopRecoveryStrategy {
        // Scroll loops -> go back
        if loopType.contains("Scroll loop") {
            if canGoBack {
                return .goBack
            }
            return .admitFailure(reason: "Stuck scrolling with no back history")
        }

        // Click loops with scroll-type content -> try scrolling to reveal new elements
        if loopType.contains("clicking same") || loopType.contains("Oscillating") {
            let hasScrollActions = recentActions.contains { $0.type == "scroll" }
            if !hasScrollActions {
                return .scrollDown
            }
            if canGoBack {
                return .goBack
            }
            return .admitFailure(reason: "Stuck clicking with no alternatives")
        }

        // No back history -> admit failure
        if !canGoBack {
            return .admitFailure(reason: "No navigation history available to recover")
        }

        return .goBack
    }

    /// Detect if the agent is stuck in a loop pattern.
    /// Returns a description of the loop type if detected, nil otherwise.
    func detectLoop() -> String? {
        let actions = recentActions

        // Need at least 4 actions to detect patterns
        guard actions.count >= 4 else { return nil }

        // Suppress false positives: if the agent is visiting new URLs, it's making progress
        if isVisitingNewURLs {
            // Only detect the most severe patterns (exact same action 4x)
            let lastFour = Array(actions.suffix(4))
            if Set(lastFour).count == 1 {
                return "Same action repeated 4 times"
            }
            return nil
        }

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

        // Pattern 3: Same action type on different elements
        if actions.count >= 5 {
            let lastFiveTypes = actions.suffix(5).map { $0.type }
            if Set(lastFiveTypes).count == 1 && lastFiveTypes[0] == "click" {
                let lastFiveTargets = Set(actions.suffix(5).map { $0.target })
                if lastFiveTargets.count <= 2 {
                    return "Repeatedly clicking same elements"
                }
            }
        }

        // Pattern 4: Scroll loop (scrolling same direction repeatedly)
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
}
