import Foundation

/// Classifies raw SSE JSON chunks into typed StreamChunk values.
///
/// This processor handles the differences between API providers:
/// - Claude uses `delta.thinking` for reasoning traces
/// - OpenAI uses `delta.reasoning_content`
/// - Other providers may use `delta.reasoning`
///
/// Regular content always comes from `delta.content`.
struct StreamingResponseProcessor {

    /// Represents a typed chunk from the streaming LLM response.
    enum StreamChunk {
        case content(String)
        case thinking(String)
        case finishReason(String)
    }

    /// Process a single SSE JSON string and return any stream chunks found.
    ///
    /// A single SSE event can produce both a thinking chunk and a content chunk,
    /// so this returns an array rather than an optional.
    func processSSEEvent(_ jsonString: String) -> [StreamChunk] {
        guard let data = jsonString.data(using: .utf8) else {
            Log.Agent.debug("StreamingResponseProcessor: Failed to convert SSE event to UTF-8 data (first 200 chars): \(String(jsonString.prefix(200)))")
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.Agent.debug("StreamingResponseProcessor: Failed to parse SSE JSON (first 200 chars): \(String(jsonString.prefix(200)))")
            return []
        }

        guard let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first else {
            Log.Agent.debug("StreamingResponseProcessor: Missing or empty 'choices' array in SSE event")
            return []
        }

        var chunks: [StreamChunk] = []

        // Extract finish_reason if present
        if let finishReason = firstChoice["finish_reason"] as? String {
            chunks.append(.finishReason(finishReason))
        }

        guard let delta = firstChoice["delta"] as? [String: Any] else {
            // No delta is normal for the final event that only has finish_reason
            return chunks
        }

        // Check for reasoning/thinking content (Claude extended thinking, OpenAI reasoning)
        // Different APIs use different field names for reasoning traces
        if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
            chunks.append(.thinking(thinking))
        } else if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            chunks.append(.thinking(reasoning))
        } else if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
            chunks.append(.thinking(reasoning))
        }

        // Regular content
        if let content = delta["content"] as? String, !content.isEmpty {
            chunks.append(.content(content))
        }

        return chunks
    }
}
