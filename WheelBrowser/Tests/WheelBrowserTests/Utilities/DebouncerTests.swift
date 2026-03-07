import Testing
import Foundation
@testable import WheelBrowser

@Suite("Debouncer Tests")
struct DebouncerTests {

    @Test("Debounced action fires after delay")
    func actionFiresAfterDelay() async throws {
        let debouncer = Debouncer(delay: .milliseconds(50))
        let counter = Counter()

        await debouncer.debounce {
            await counter.increment(by: 1)
        }

        try await waitUntil {
            await counter.value == 1
        }

        let value = await counter.value
        #expect(value == 1)
    }

    @Test("Rapid invocations only fire last action")
    func rapidInvocationsOnlyFireLast() async throws {
        let debouncer = Debouncer(delay: .milliseconds(50))
        let counter = Counter()

        // Rapidly queue multiple debounces - only last should fire
        await debouncer.debounce {
            await counter.increment(by: 1)
        }
        await debouncer.debounce {
            await counter.increment(by: 10)
        }
        await debouncer.debounce {
            await counter.increment(by: 100)
        }

        try await waitUntil {
            await counter.value == 100
        }

        let value = await counter.value
        #expect(value == 100) // Only last action should fire
    }

    @Test("New call cancels pending action")
    func newCallCancelsPending() async throws {
        let debouncer = Debouncer(delay: .milliseconds(100))
        let counter = Counter()

        await debouncer.debounce {
            await counter.increment(by: 1) // First action
        }

        // Wait a bit, but less than the delay
        try await Task.sleep(for: .milliseconds(30))

        await debouncer.debounce {
            await counter.increment(by: 10) // Second action
        }

        try await waitUntil {
            await counter.value == 10
        }

        let value = await counter.value
        #expect(value == 10) // Only second action should fire
    }

    @Test("Cancel prevents action from firing")
    func cancelPreventsAction() async throws {
        let debouncer = Debouncer(delay: .milliseconds(50))
        let counter = Counter()

        await debouncer.debounce {
            await counter.increment(by: 1)
        }

        // Cancel immediately
        await debouncer.cancel()

        // Wait past the delay
        try await Task.sleep(for: .milliseconds(250))

        let value = await counter.value
        #expect(value == 0) // Should not have fired
    }

    @Test("Default delay is 50ms")
    func defaultDelay() async throws {
        let debouncer = Debouncer()
        let counter = Counter()

        await debouncer.debounce {
            await counter.increment(by: 1)
        }

        // Wait less than 50ms
        try await Task.sleep(for: .milliseconds(20))
        let valueBefore = await counter.value
        #expect(valueBefore == 0)

        // Wait for the rest plus buffer
        try await waitUntil {
            await counter.value == 1
        }
        let valueAfter = await counter.value
        #expect(valueAfter == 1)
    }

    @Test("Multiple sequential debounces work correctly")
    func multipleSequentialDebounces() async throws {
        let debouncer = Debouncer(delay: .milliseconds(30))
        let counter = Counter()

        // First debounce
        await debouncer.debounce {
            await counter.increment(by: 1)
        }
        try await waitUntil {
            await counter.value == 1
        }

        // Second debounce (after first completed)
        await debouncer.debounce {
            await counter.increment(by: 10)
        }
        try await waitUntil {
            await counter.value == 11
        }

        let value = await counter.value
        #expect(value == 11) // 1 + 10
    }

    @Test("Debouncer is actor-safe")
    func actorSafe() async throws {
        let debouncer = Debouncer(delay: .milliseconds(20))
        let counter = Counter()

        // Fire multiple concurrent debounces
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    await debouncer.debounce {
                        await counter.increment(by: i)
                    }
                }
            }
        }

        try await waitUntil {
            await counter.value > 0
        }

        // Only the last value should have been added (or one of the later ones)
        // Due to concurrent execution, we can't guarantee which one is "last"
        // but only one should have run
        let value = await counter.value
        #expect(value > 0)
        #expect(value <= 10)
    }
}

private enum DebouncerTestError: Error {
    case timedOut
}

private func waitUntil(
    timeout: Duration = .milliseconds(500),
    pollInterval: Duration = .milliseconds(10),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if await condition() {
            return
        }

        try await Task.sleep(for: pollInterval)
    }

    throw DebouncerTestError.timedOut
}

// Helper actor for thread-safe counting
actor Counter {
    var value: Int = 0

    func increment(by amount: Int) {
        value += amount
    }
}
