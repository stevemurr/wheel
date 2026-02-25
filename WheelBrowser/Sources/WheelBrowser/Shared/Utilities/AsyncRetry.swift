import Foundation

/// Executes an async operation with exponential backoff retry logic
/// - Parameters:
///   - maxAttempts: Maximum number of attempts before giving up (default: 3)
///   - initialDelay: Initial delay in seconds before first retry (default: 1.0)
///   - maxDelay: Maximum delay cap in seconds (default: 30.0)
///   - shouldRetry: Closure to determine if an error should be retried (default: all errors)
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: The last error if all attempts fail
func withExponentialBackoff<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    maxDelay: TimeInterval = 30.0,
    shouldRetry: @escaping (Error) -> Bool = { _ in true },
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error

            // Check if we should retry this error
            guard shouldRetry(error) else {
                throw error
            }

            // Don't wait after the last attempt
            if attempt < maxAttempts {
                // Calculate backoff: initialDelay * 2^(attempt-1), capped at maxDelay
                let backoffSeconds = min(initialDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            }
        }
    }

    throw lastError ?? AsyncRetryError.unknownError
}

/// Executes an async operation with exponential backoff, providing attempt information
/// - Parameters:
///   - maxAttempts: Maximum number of attempts before giving up
///   - initialDelay: Initial delay in seconds before first retry
///   - maxDelay: Maximum delay cap in seconds
///   - onRetry: Called before each retry with the attempt number and error
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: The last error if all attempts fail
func withExponentialBackoff<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    maxDelay: TimeInterval = 30.0,
    onRetry: @escaping (Int, Error) async -> Void,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error

            // Don't call onRetry after the last attempt
            if attempt < maxAttempts {
                await onRetry(attempt, error)

                // Calculate backoff
                let backoffSeconds = min(initialDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            }
        }
    }

    throw lastError ?? AsyncRetryError.unknownError
}

enum AsyncRetryError: Error {
    case unknownError
}
