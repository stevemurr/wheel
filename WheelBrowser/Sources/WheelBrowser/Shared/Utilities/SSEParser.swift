import Foundation

/// Parses Server-Sent Events (SSE) from an async byte stream.
/// Yields the JSON payload string for each `data: ` line, stopping at `[DONE]`.
struct SSEParser: AsyncSequence, Sendable {
    typealias Element = String

    let bytes: URLSession.AsyncBytes

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: any AsyncIteratorProtocol

        mutating func next() async throws -> String? {
            while let line = try await iterator.next() {
                guard let str = line as? String else { continue }
                guard str.hasPrefix("data: ") else { continue }

                let payload = String(str.dropFirst(6))
                if payload == "[DONE]" {
                    return nil
                }

                return payload
            }
            return nil
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: bytes.lines.makeAsyncIterator())
    }
}

extension URLSession.AsyncBytes {
    /// Parse this byte stream as Server-Sent Events, yielding JSON payloads
    var sseEvents: SSEParser {
        SSEParser(bytes: self)
    }
}
