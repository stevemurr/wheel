import Testing
@testable import WheelBrowser

@Suite("LoopDetector Tests")
struct LoopDetectorTests {

    // MARK: - Same Action Repeated Tests

    @Test("Detects same action repeated N times")
    func detectsSameActionRepeated() {
        let detector = LoopDetector<String>()

        // Record the same action 4 times (default threshold)
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        let result = detector.recordAction("click(1)")

        if case .sameActionRepeated(let count) = result {
            #expect(count == 4)
        } else {
            Issue.record("Expected sameActionRepeated loop type")
        }
    }

    @Test("No loop with varied actions")
    func noLoopWithVariedActions() {
        let detector = LoopDetector<String>()

        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        detector.recordAction("type(3, 'text')")
        let result = detector.recordAction("scroll(down)")

        #expect(result == nil)
    }

    @Test("Respects custom repeat threshold")
    func customRepeatThreshold() {
        let config = LoopDetector<String>.Configuration(repeatThreshold: 3, historySize: 8)
        let detector = LoopDetector<String>(configuration: config)

        // Need at least 4 actions for pattern detection (guard in detectLoop)
        detector.recordAction("warmup")
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        let result = detector.recordAction("click(1)")

        if case .sameActionRepeated(let count) = result {
            #expect(count == 3)
        } else {
            Issue.record("Expected sameActionRepeated with threshold 3, got \(String(describing: result))")
        }
    }

    // MARK: - Oscillation Tests

    @Test("Detects oscillation pattern A-B-A-B")
    func detectsOscillation() {
        let detector = LoopDetector<String>()

        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        detector.recordAction("click(1)")
        let result = detector.recordAction("click(2)")

        if case .oscillating = result {
            // Success
        } else {
            Issue.record("Expected oscillating loop type")
        }
    }

    @Test("No oscillation with same action")
    func noOscillationWithSameAction() {
        let detector = LoopDetector<String>()

        // A-A-A-A is not oscillation (same action repeated)
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        let result = detector.recordAction("click(1)")

        // Should be sameActionRepeated, not oscillating
        if case .oscillating = result {
            Issue.record("Should not detect oscillation for same repeated action")
        }
    }

    // MARK: - Three Action Cycle Tests

    @Test("Detects three action cycle A-B-C-A-B-C")
    func detectsThreeActionCycle() {
        let detector = LoopDetector<String>()

        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        detector.recordAction("click(3)")
        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        let result = detector.recordAction("click(3)")

        if case .threeActionCycle = result {
            // Success
        } else {
            Issue.record("Expected threeActionCycle loop type, got \(String(describing: result))")
        }
    }

    // MARK: - Same Type Loop Tests

    @Test("Detects same type repeated with extractor")
    func detectsSameTypeRepeated() {
        let detector = LoopDetector<String>(
            configuration: .init(sameTypeThreshold: 4),
            actionTypeExtractor: { action in
                if let parenIndex = action.firstIndex(of: "(") {
                    return String(action[..<parenIndex]).lowercased()
                }
                return action.lowercased()
            }
        )

        // All clicks on different targets but same type
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        let result = detector.recordAction("click(1)")

        if case .sameTypeRepeated(let type, let count) = result {
            #expect(type == "click")
            #expect(count == 4)
        } else {
            Issue.record("Expected sameTypeRepeated loop type, got \(String(describing: result))")
        }
    }

    @Test("No same type loop without extractor")
    func noSameTypeLoopWithoutExtractor() {
        let detector = LoopDetector<String>()

        // Without type extractor, different actions are different
        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        detector.recordAction("click(3)")
        detector.recordAction("click(4)")
        let result = detector.recordAction("click(5)")

        // Should not detect same type loop without extractor
        if case .sameTypeRepeated = result {
            Issue.record("Should not detect sameTypeRepeated without extractor")
        }
    }

    // MARK: - Scroll Loop Tests

    @Test("Detects scroll loop")
    func detectsScrollLoop() {
        let detector = LoopDetector<String>(
            configuration: .init(repeatThreshold: 10, scrollThreshold: 3), // High repeat threshold
            scrollDirectionExtractor: { action in
                let lower = action.lowercased()
                if lower.contains("scroll") {
                    if lower.contains("down") { return "down" }
                    if lower.contains("up") { return "up" }
                }
                return nil
            }
        )

        // Use different scroll actions that all go "down" but aren't identical
        // This avoids triggering sameActionRepeated before scrollLoop
        detector.recordAction("scroll_down_1")
        detector.recordAction("scroll_down_2")
        detector.recordAction("scroll_down_3")
        detector.recordAction("scroll_down_4")
        let result = detector.recordAction("scroll_down_5")

        if case .scrollLoop = result {
            // Success
        } else {
            Issue.record("Expected scrollLoop, got \(String(describing: result))")
        }
    }

    @Test("No scroll loop with alternating directions")
    func noScrollLoopWithAlternatingDirections() {
        let detector = LoopDetector<String>(
            configuration: .init(scrollThreshold: 3),
            scrollDirectionExtractor: { action in
                let lower = action.lowercased()
                if lower.contains("scroll") {
                    if lower.contains("down") { return "down" }
                    if lower.contains("up") { return "up" }
                }
                return nil
            }
        )

        detector.recordAction("scroll(down)")
        detector.recordAction("scroll(up)")
        detector.recordAction("scroll(down)")
        detector.recordAction("scroll(up)")
        let result = detector.recordAction("scroll(down)")

        // Should detect oscillation or no loop, not scroll loop
        if case .scrollLoop = result {
            Issue.record("Should not detect scroll loop with alternating directions")
        }
    }

    // MARK: - Reset and History Tests

    @Test("Reset clears action history")
    func resetClearsHistory() {
        let detector = LoopDetector<String>()

        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")

        detector.reset()

        #expect(detector.actionHistory.isEmpty)
        #expect(detector.detectLoop() == nil)
    }

    @Test("History respects size limit")
    func historyRespectsLimit() {
        let config = LoopDetector<String>.Configuration(historySize: 4)
        let detector = LoopDetector<String>(configuration: config)

        for i in 1...10 {
            detector.recordAction("action\(i)")
        }

        #expect(detector.actionHistory.count == 4)
        #expect(detector.actionHistory.last == "action10")
    }

    // MARK: - Minimum Actions Tests

    @Test("No loop detection with fewer than 4 actions")
    func noLoopWithFewActions() {
        let detector = LoopDetector<String>()

        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        let result = detector.recordAction("click(1)")

        #expect(result == nil)
    }

    // MARK: - String-Based Convenience

    @Test("String-based detector extracts action types correctly")
    func stringBasedExtractsTypes() {
        let detector = LoopDetector<String>.stringBased(
            configuration: .init(sameTypeThreshold: 4)
        )

        // Using click(id) format
        detector.recordAction("click(1)")
        detector.recordAction("click(1)")
        detector.recordAction("click(2)")
        let result = detector.recordAction("click(1)")

        if case .sameTypeRepeated(let type, _) = result {
            #expect(type == "click")
        } else {
            Issue.record("Expected sameTypeRepeated for string-based detector")
        }
    }

    @Test("String-based detector extracts scroll direction")
    func stringBasedExtractsScrollDirection() {
        let detector = LoopDetector<String>.stringBased(
            configuration: .init(repeatThreshold: 10, scrollThreshold: 3) // High repeat threshold
        )

        // Use different scroll actions that all extract to "down" direction
        detector.recordAction("scroll_down(1)")
        detector.recordAction("scroll_down(2)")
        detector.recordAction("scroll_down(3)")
        detector.recordAction("scroll_down(4)")
        let result = detector.recordAction("scroll_down(5)")

        if case .scrollLoop = result {
            // Success
        } else {
            Issue.record("Expected scrollLoop for string-based detector, got \(String(describing: result))")
        }
    }

    // MARK: - Loop Type Descriptions

    @Test("Loop type descriptions are formatted correctly")
    func loopTypeDescriptions() {
        #expect(LoopDetector<String>.LoopType.sameActionRepeated(count: 4).description == "Same action repeated 4 times")
        #expect(LoopDetector<String>.LoopType.oscillating.description == "Oscillating between two actions")
        #expect(LoopDetector<String>.LoopType.sameTypeRepeated(type: "click", count: 5).description == "Repeatedly performing click (5 times)")
        #expect(LoopDetector<String>.LoopType.scrollLoop.description == "Scroll loop without progress")
        #expect(LoopDetector<String>.LoopType.threeActionCycle.description == "Three-action cycle detected")
    }
}
