import Foundation

/// Pre-action state capture for computing deltas after an action
typealias PreActionState = (url: String, title: String, elementCount: Int, captchaDetected: Bool)

/// Protocol for interacting with web pages, enabling dependency injection for testing
@MainActor
protocol BrowserBridge: AnyObject {
    func snapshot() async throws -> PageSnapshot
    func click(elementId: Int, modifiers: ClickModifiers) async throws
    func type(elementId: Int, text: String) async throws
    func pressEnter() async throws
    func scroll(deltaX: Double, deltaY: Double) async throws
    func scrollToTop() async throws
    func scrollToBottom() async throws
    func waitForLoad(timeout: TimeInterval, stableThreshold: TimeInterval) async throws
    func readText(elementId: Int) async throws -> String
    func revalidateElement(elementId: Int, expectedTag: String?, expectedText: String?) async throws -> Int
    func capturePreActionState() async -> PreActionState
    func quickDelta(before: PreActionState) async -> ActionDelta
}

/// Convenience methods with default parameter values
extension BrowserBridge {
    func click(elementId: Int) async throws {
        try await click(elementId: elementId, modifiers: .none)
    }

    func scroll(deltaY: Double) async throws {
        try await scroll(deltaX: 0, deltaY: deltaY)
    }

    func waitForLoad(timeout: TimeInterval = 5.0) async throws {
        try await waitForLoad(timeout: timeout, stableThreshold: 0.5)
    }
}

/// Protocol for providing a BrowserBridge for a given tab
@MainActor
protocol BrowserBridgeProvider: AnyObject {
    func bridge(for tabId: UUID) -> (any BrowserBridge)?
}
