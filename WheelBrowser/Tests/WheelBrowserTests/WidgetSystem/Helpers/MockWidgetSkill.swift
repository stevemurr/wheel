import Foundation
@testable import WheelBrowser

/// A reusable mock skill for testing pipeline execution without real network calls.
final class MockWidgetSkill: WidgetSkill, @unchecked Sendable {
    let name: SkillName
    let paramSchema: String = "{}"

    private let lock = NSLock()
    private let cannedResult: Any
    private let errorToThrow: Error?
    private let delay: TimeInterval

    private(set) var invocationCount = 0
    private(set) var lastParams: [String: Any]?

    init(
        name: SkillName,
        result: Any = [] as [Any],
        error: Error? = nil,
        delay: TimeInterval = 0
    ) {
        self.name = name
        self.cannedResult = result
        self.errorToThrow = error
        self.delay = delay
    }

    func execute(params: [String: Any]) async throws -> Any {
        lock.lock()
        invocationCount += 1
        lastParams = params
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if let error = errorToThrow {
            throw error
        }

        return cannedResult
    }
}
