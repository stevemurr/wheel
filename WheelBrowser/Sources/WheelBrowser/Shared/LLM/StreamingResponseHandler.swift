import Foundation

/// A generic handler for buffered LLM streaming responses.
/// Batches incoming chunks intelligently based on markdown structure boundaries
/// to reduce UI updates while maintaining visual responsiveness.
@MainActor
public final class StreamingResponseHandler {
    // MARK: - Configuration

    /// Configuration for the streaming handler
    public struct Configuration {
        /// Maximum time between forced updates (in seconds)
        public var maxUpdateInterval: TimeInterval = 0.1

        /// Maximum buffer size before forcing a flush (in characters)
        public var maxBufferSize: Int = 200

        public init(
            maxUpdateInterval: TimeInterval = 0.1,
            maxBufferSize: Int = 200
        ) {
            self.maxUpdateInterval = maxUpdateInterval
            self.maxBufferSize = maxBufferSize
        }

        /// Default configuration optimized for chat responses
        public static let `default` = Configuration()

        /// Configuration for faster updates (lower latency)
        public static let lowLatency = Configuration(maxUpdateInterval: 0.05, maxBufferSize: 100)

        /// Configuration for reduced CPU usage (higher batching)
        public static let highBatching = Configuration(maxUpdateInterval: 0.2, maxBufferSize: 400)
    }

    // MARK: - State

    private var buffer: String = ""
    private var pendingChunk: String = ""
    private var lastUpdateTime: Date = Date()

    private let configuration: Configuration
    private let onUpdate: (String) -> Void

    // MARK: - Initialization

    /// Creates a new streaming response handler
    /// - Parameters:
    ///   - configuration: Configuration for buffering behavior
    ///   - onUpdate: Callback invoked when the buffer should be flushed to the UI
    public init(
        configuration: Configuration = .default,
        onUpdate: @escaping (String) -> Void
    ) {
        self.configuration = configuration
        self.onUpdate = onUpdate
    }

    // MARK: - Public API

    /// Process an incoming chunk from the stream
    /// - Parameter chunk: The text chunk received from the LLM
    public func processChunk(_ chunk: String) {
        pendingChunk += chunk

        let now = Date()
        let timeSinceUpdate = now.timeIntervalSince(lastUpdateTime)

        // Flush on complete markdown structures or timeout
        if shouldFlushBuffer(pendingChunk) || timeSinceUpdate >= configuration.maxUpdateInterval {
            buffer += pendingChunk
            pendingChunk = ""
            lastUpdateTime = now
            onUpdate(buffer)
        }
    }

    /// Finalize the stream, flushing any remaining content
    /// - Returns: The complete accumulated content
    @discardableResult
    public func finalize() -> String {
        // Flush any remaining pending content
        if !pendingChunk.isEmpty {
            buffer += pendingChunk
            pendingChunk = ""
        }

        onUpdate(buffer)
        return buffer
    }

    /// Reset the handler for reuse
    public func reset() {
        buffer = ""
        pendingChunk = ""
        lastUpdateTime = Date()
    }

    /// Get the current accumulated content
    public var currentContent: String {
        buffer + pendingChunk
    }

    // MARK: - Buffer Analysis

    /// Detects complete markdown structures that are safe flush points.
    /// This reduces UI updates while ensuring meaningful visual progress.
    private func shouldFlushBuffer(_ buffer: String) -> Bool {
        guard !buffer.isEmpty else { return false }

        // Paragraph break - most common flush point
        if buffer.hasSuffix("\n\n") {
            return true
        }

        // Code block boundaries
        if buffer.hasSuffix("```\n") || buffer.hasSuffix("```") {
            return true
        }

        // LaTeX block boundaries
        if buffer.hasSuffix("$$\n") || buffer.hasSuffix("$$") {
            return true
        }

        // End of sentence followed by space (natural reading break)
        if buffer.count >= 2 {
            let lastTwo = String(buffer.suffix(2))
            if lastTwo == ". " || lastTwo == "! " || lastTwo == "? " {
                return true
            }
        }

        // List item complete (newline after list content)
        if buffer.contains("\n") {
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if let lastLine = lines.last, lastLine.isEmpty {
                // Previous line was complete
                if lines.count >= 2 {
                    let prevLine = String(lines[lines.count - 2])
                    // Check if it was a list item or heading
                    let trimmed = prevLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                       trimmed.hasPrefix("# ") || trimmed.hasPrefix("> ") ||
                       trimmed.first?.isNumber == true && trimmed.contains(". ") {
                        return true
                    }
                }
            }
        }

        // Heading complete
        if buffer.hasSuffix("\n") && buffer.contains("#") {
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                let prevLine = String(lines[lines.count - 2])
                if prevLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    return true
                }
            }
        }

        // Table row complete
        if buffer.hasSuffix("|\n") {
            return true
        }

        // Fallback: flush on any newline if buffer is getting large
        if buffer.count > configuration.maxBufferSize && buffer.hasSuffix("\n") {
            return true
        }

        return false
    }
}

// MARK: - Convenience for AsyncThrowingStream

extension StreamingResponseHandler {
    /// Process an entire async stream of chunks
    /// - Parameter stream: The async stream to process
    /// - Returns: The complete accumulated content
    public func process<S: AsyncSequence>(stream: S) async throws -> String where S.Element == String {
        for try await chunk in stream {
            processChunk(chunk)
        }
        return finalize()
    }
}
