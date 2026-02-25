import Foundation

/// Detects when an agent or process is stuck in a repetitive loop pattern.
/// Useful for browser automation, AI agents, or any iterative process that
/// might get stuck repeating the same actions.
public final class LoopDetector<Action: Hashable> {
    // MARK: - Types

    /// The type of loop pattern detected
    public enum LoopType: CustomStringConvertible {
        /// Same action repeated N times consecutively
        case sameActionRepeated(count: Int)
        /// Oscillating between two actions (A-B-A-B)
        case oscillating
        /// Same type of action on different targets
        case sameTypeRepeated(type: String, count: Int)
        /// Scrolling in one direction without progress
        case scrollLoop
        /// Three-action cycle (A-B-C-A-B-C)
        case threeActionCycle

        public var description: String {
            switch self {
            case .sameActionRepeated(let count):
                return "Same action repeated \(count) times"
            case .oscillating:
                return "Oscillating between two actions"
            case .sameTypeRepeated(let type, let count):
                return "Repeatedly performing \(type) (\(count) times)"
            case .scrollLoop:
                return "Scroll loop without progress"
            case .threeActionCycle:
                return "Three-action cycle detected"
            }
        }
    }

    /// Configuration for loop detection thresholds
    public struct Configuration {
        /// Number of identical actions to consider a repeat loop
        public var repeatThreshold: Int = 4
        /// Number of actions of the same type to detect type-based loops
        public var sameTypeThreshold: Int = 5
        /// Number of scrolls in same direction to detect scroll loops
        public var scrollThreshold: Int = 4
        /// Maximum number of recent actions to track
        public var historySize: Int = 8

        public init(
            repeatThreshold: Int = 4,
            sameTypeThreshold: Int = 5,
            scrollThreshold: Int = 4,
            historySize: Int = 8
        ) {
            self.repeatThreshold = repeatThreshold
            self.sameTypeThreshold = sameTypeThreshold
            self.scrollThreshold = scrollThreshold
            self.historySize = historySize
        }
    }

    /// Default configuration preset
    public static var defaultConfiguration: Configuration { Configuration() }

    /// More aggressive detection configuration (fewer actions before flagging)
    public static var sensitiveConfiguration: Configuration {
        Configuration(
            repeatThreshold: 3,
            sameTypeThreshold: 4,
            scrollThreshold: 3,
            historySize: 6
        )
    }

    // MARK: - State

    private var recentActions: [Action] = []
    private let configuration: Configuration

    /// Optional function to extract action type for type-based detection
    private let actionTypeExtractor: ((Action) -> String)?

    /// Optional function to detect if an action is a scroll action
    private let scrollDirectionExtractor: ((Action) -> String?)?

    // MARK: - Initialization

    /// Creates a new loop detector
    /// - Parameters:
    ///   - configuration: Detection configuration
    ///   - actionTypeExtractor: Optional function to extract action type (e.g., "click", "type")
    ///   - scrollDirectionExtractor: Optional function to extract scroll direction if action is a scroll
    public init(
        configuration: Configuration = Configuration(),
        actionTypeExtractor: ((Action) -> String)? = nil,
        scrollDirectionExtractor: ((Action) -> String?)? = nil
    ) {
        self.configuration = configuration
        self.actionTypeExtractor = actionTypeExtractor
        self.scrollDirectionExtractor = scrollDirectionExtractor
    }

    // MARK: - Public API

    /// Record a new action and check for loops
    /// - Parameter action: The action to record
    /// - Returns: The detected loop type, if any
    @discardableResult
    public func recordAction(_ action: Action) -> LoopType? {
        recentActions.append(action)

        // Keep only recent history
        if recentActions.count > configuration.historySize {
            recentActions.removeFirst()
        }

        return detectLoop()
    }

    /// Check if currently in a loop state
    /// - Returns: The detected loop type, if any
    public func detectLoop() -> LoopType? {
        let actions = recentActions

        // Need minimum actions for pattern detection
        guard actions.count >= 4 else { return nil }

        // Pattern 1: Same action repeated consecutively
        if let repeated = detectRepeatLoop(actions) {
            return repeated
        }

        // Pattern 2: Oscillating between 2 actions (A-B-A-B)
        if let oscillating = detectOscillation(actions) {
            return oscillating
        }

        // Pattern 3: Same action type on different targets
        if let sameType = detectSameTypeLoop(actions) {
            return sameType
        }

        // Pattern 4: Scroll loop
        if let scroll = detectScrollLoop(actions) {
            return scroll
        }

        // Pattern 5: Three-action cycle (A-B-C-A-B-C)
        if let cycle = detectThreeActionCycle(actions) {
            return cycle
        }

        return nil
    }

    /// Clear the action history
    public func reset() {
        recentActions.removeAll()
    }

    /// Get the current action history
    public var actionHistory: [Action] {
        recentActions
    }

    // MARK: - Pattern Detection

    private func detectRepeatLoop(_ actions: [Action]) -> LoopType? {
        let threshold = configuration.repeatThreshold
        guard actions.count >= threshold else { return nil }

        let lastN = Array(actions.suffix(threshold))
        if Set(lastN).count == 1 {
            return .sameActionRepeated(count: threshold)
        }
        return nil
    }

    private func detectOscillation(_ actions: [Action]) -> LoopType? {
        guard actions.count >= 4 else { return nil }

        let a1 = actions[actions.count - 4]
        let a2 = actions[actions.count - 3]
        let a3 = actions[actions.count - 2]
        let a4 = actions[actions.count - 1]

        if a1 == a3 && a2 == a4 && a1 != a2 {
            return .oscillating
        }
        return nil
    }

    private func detectSameTypeLoop(_ actions: [Action]) -> LoopType? {
        guard let extractor = actionTypeExtractor else { return nil }

        let threshold = configuration.sameTypeThreshold
        guard actions.count >= threshold else { return nil }

        let lastN = actions.suffix(threshold)
        let types = lastN.map { extractor($0) }

        if Set(types).count == 1 {
            let type = types[0]
            // For click loops, also check if clicking same few targets
            let uniqueActions = Set(lastN)
            if uniqueActions.count <= 2 {
                return .sameTypeRepeated(type: type, count: threshold)
            }
        }
        return nil
    }

    private func detectScrollLoop(_ actions: [Action]) -> LoopType? {
        guard let extractor = scrollDirectionExtractor else { return nil }

        let threshold = configuration.scrollThreshold + 2 // Need extra for context
        guard actions.count >= threshold else { return nil }

        let lastN = actions.suffix(threshold)
        let scrollActions = lastN.compactMap { extractor($0) }

        if scrollActions.count >= configuration.scrollThreshold {
            let directions = Set(scrollActions)
            if directions.count == 1 {
                return .scrollLoop
            }
        }
        return nil
    }

    private func detectThreeActionCycle(_ actions: [Action]) -> LoopType? {
        guard actions.count >= 6 else { return nil }

        let a1 = actions[actions.count - 6]
        let a2 = actions[actions.count - 5]
        let a3 = actions[actions.count - 4]
        let a4 = actions[actions.count - 3]
        let a5 = actions[actions.count - 2]
        let a6 = actions[actions.count - 1]

        if a1 == a4 && a2 == a5 && a3 == a6 {
            return .threeActionCycle
        }
        return nil
    }
}

// MARK: - String-based Convenience

extension LoopDetector where Action == String {
    /// Create a detector optimized for string-based action descriptions
    public static func stringBased(configuration: Configuration = Configuration()) -> LoopDetector<String> {
        LoopDetector<String>(
            configuration: configuration,
            actionTypeExtractor: { action in
                // Extract action type from common formats like "click(5)" or "type(3, 'text')"
                if let parenIndex = action.firstIndex(of: "(") {
                    return String(action[..<parenIndex]).lowercased()
                }
                return action.lowercased()
            },
            scrollDirectionExtractor: { action in
                let lower = action.lowercased()
                if lower.contains("scroll") {
                    if lower.contains("down") { return "down" }
                    if lower.contains("up") { return "up" }
                    if lower.contains("left") { return "left" }
                    if lower.contains("right") { return "right" }
                }
                return nil
            }
        )
    }
}
