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
        }
    }
}

/// Agent-specific loop detector that tracks NormalizedAction history
/// and detects various stuck patterns.
final class AgentLoopDetector {
    /// History of recent actions for semantic loop detection
    private(set) var recentActions: [NormalizedAction] = []
    /// Track consecutive parse failures for backoff
    private(set) var consecutiveParseFailures: Int = 0
    /// Track loop recovery attempts
    private(set) var loopRecoveryAttempts: Int = 0

    let maxConsecutiveParseFailures = 3
    let maxLoopRecoveryAttempts = 2

    /// Record a new normalized action
    func recordAction(_ action: NormalizedAction) {
        recentActions.append(action)
        // Keep only last 8 actions for pattern detection
        if recentActions.count > 8 {
            recentActions.removeFirst()
        }
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
    }

    /// Detect if the agent is stuck in a loop pattern.
    /// Returns a description of the loop type if detected, nil otherwise.
    func detectLoop() -> String? {
        let actions = recentActions

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
