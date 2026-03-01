import Foundation
@testable import WheelBrowser

/// Mock browser bridge that simulates page interactions for deterministic unit testing.
///
/// Configure with snapshots to return on each `snapshot()` call, and inspect
/// recorded actions to verify the agent took the expected steps.
@MainActor
final class MockBrowserBridge: BrowserBridge {
    /// Snapshots returned in order on each `snapshot()` call. Cycles the last one if exhausted.
    private var snapshots: [PageSnapshot]
    private var snapshotIndex = 0

    /// All actions recorded during the test
    private(set) var recordedActions: [RecordedAction] = []

    /// Current simulated URL (updated by navigate actions)
    var currentURL: String
    var currentTitle: String

    enum RecordedAction: Equatable {
        case click(elementId: Int, modifiers: ClickModifiers)
        case type(elementId: Int, text: String)
        case pressEnter
        case scroll(deltaX: Double, deltaY: Double)
        case scrollToTop
        case scrollToBottom
        case readText(elementId: Int)
        case waitForLoad(timeout: TimeInterval)
        case revalidateElement(elementId: Int)
    }

    init(snapshots: [PageSnapshot], initialURL: String = "https://example.com", initialTitle: String = "Example") {
        self.snapshots = snapshots
        self.currentURL = initialURL
        self.currentTitle = initialTitle
    }

    func snapshot() async throws -> PageSnapshot {
        guard !snapshots.isEmpty else {
            return PageSnapshotFactory.empty()
        }
        let snap = snapshots[min(snapshotIndex, snapshots.count - 1)]
        snapshotIndex += 1
        return snap
    }

    func click(elementId: Int, modifiers: ClickModifiers) async throws {
        recordedActions.append(.click(elementId: elementId, modifiers: modifiers))
    }

    func type(elementId: Int, text: String) async throws {
        recordedActions.append(.type(elementId: elementId, text: text))
    }

    func pressEnter() async throws {
        recordedActions.append(.pressEnter)
    }

    func scroll(deltaX: Double, deltaY: Double) async throws {
        recordedActions.append(.scroll(deltaX: deltaX, deltaY: deltaY))
    }

    func scrollToTop() async throws {
        recordedActions.append(.scrollToTop)
    }

    func scrollToBottom() async throws {
        recordedActions.append(.scrollToBottom)
    }

    func waitForLoad(timeout: TimeInterval, stableThreshold: TimeInterval) async throws {
        recordedActions.append(.waitForLoad(timeout: timeout))
    }

    func readText(elementId: Int) async throws -> String {
        recordedActions.append(.readText(elementId: elementId))
        return "Mock text content near element \(elementId)"
    }

    func revalidateElement(elementId: Int, expectedTag: String?, expectedText: String?) async throws -> Int {
        recordedActions.append(.revalidateElement(elementId: elementId))
        return elementId // Always confirms the element is still valid
    }

    func capturePreActionState() async -> PreActionState {
        return (url: currentURL, title: currentTitle, elementCount: 10, captchaDetected: false)
    }

    func quickDelta(before: PreActionState) async -> ActionDelta {
        return ActionDelta(
            urlChanged: before.url != currentURL,
            newURL: before.url != currentURL ? currentURL : nil,
            titleChanged: before.title != currentTitle,
            newTitle: before.title != currentTitle ? currentTitle : nil,
            elementCountBefore: before.elementCount,
            elementCountAfter: 10,
            captchaAppeared: false,
            captchaDisappeared: false
        )
    }
}

/// Mock bridge provider that returns a fixed bridge for any tab ID
@MainActor
final class MockBrowserBridgeProvider: BrowserBridgeProvider {
    let mockBridge: MockBrowserBridge

    init(bridge: MockBrowserBridge) {
        self.mockBridge = bridge
    }

    func bridge(for tabId: UUID) -> (any BrowserBridge)? {
        return mockBridge
    }
}
