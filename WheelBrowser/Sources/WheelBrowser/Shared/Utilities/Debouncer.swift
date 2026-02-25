import Foundation

/// A reusable debouncer for rate-limiting operations
actor Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .milliseconds(50)) {
        self.delay = delay
    }

    /// Debounce an async operation
    func debounce(_ operation: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    /// Cancel any pending debounced operation
    func cancel() {
        task?.cancel()
        task = nil
    }
}
