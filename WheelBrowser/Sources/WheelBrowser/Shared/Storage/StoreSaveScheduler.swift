import Foundation

@MainActor
final class StoreSaveScheduler {
    private let delay: Duration
    private var pendingTask: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    deinit {
        pendingTask?.cancel()
    }

    func schedule(_ operation: @escaping @MainActor () -> Void) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            operation()
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    func flush(_ operation: @escaping @MainActor () -> Void) {
        cancel()
        operation()
    }
}
