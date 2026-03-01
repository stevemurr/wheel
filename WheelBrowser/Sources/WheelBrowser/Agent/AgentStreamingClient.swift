import Foundation

/// Protocol for LLM communication, enabling dependency injection for testing
protocol AgentLLMClient: Sendable {
    func callLLM(prompt: String, systemPrompt: String) async throws -> String
}

/// Handles LLM API communication for the agent, including retry logic
/// and response parsing for reasoning models.
final class AgentStreamingClient: AgentLLMClient {

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Call the LLM with a prompt and system prompt, returning the content string.
    /// Includes retry logic for transient errors (5xx, 429, network).
    func callLLM(prompt: String, systemPrompt: String) async throws -> String {
        guard let baseURL = settings.llmBaseURL else {
            throw AgentError.llmNotConfigured
        }

        let endpoint = baseURL.appendingPathComponent("chat/completions")

        let body: [String: Any] = [
            "model": settings.selectedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 4000
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                if settings.useAPIKey && settings.hasAPIKey {
                    request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
                }

                request.httpBody = bodyData

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Log.Agent.error("callLLM: Invalid HTTP response type")
                    throw AgentError.llmRequestFailed("Invalid response")
                }

                Log.Agent.debug("callLLM: HTTP status \(httpResponse.statusCode)")

                // Handle retryable errors (5xx server errors, 429 rate limit)
                if httpResponse.statusCode >= 500 || httpResponse.statusCode == 429 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    Log.Agent.warning("callLLM: HTTP \(httpResponse.statusCode) (attempt \(attempt)/\(maxRetries))")
                    Log.Agent.debug("callLLM: Request details - Endpoint: \(endpoint), Model: \(settings.selectedModel), Prompt length: \(prompt.count) chars, max_tokens: 4000")
                    Log.Agent.debug("callLLM: Error response body: \(errorBody)")

                    if attempt < maxRetries {
                        let backoffSeconds = pow(2.0, Double(attempt - 1))
                        try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                        continue
                    } else {
                        throw AgentError.llmRequestFailed("HTTP \(httpResponse.statusCode) after \(maxRetries) retries: \(errorBody)")
                    }
                }

                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    Log.Agent.error("callLLM: HTTP error \(httpResponse.statusCode): \(errorMessage)")
                    throw AgentError.llmRequestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
                }

                return try parseLLMResponse(data: data)

            } catch let error as AgentError {
                lastError = error
                if case .llmRequestFailed(let msg) = error, msg.contains("HTTP 5") || msg.contains("HTTP 429") {
                    continue
                }
                throw error
            } catch {
                lastError = error
                Log.Agent.warning("callLLM: Network error (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription)")

                if attempt < maxRetries {
                    let backoffSeconds = pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                    continue
                }
            }
        }

        throw lastError ?? AgentError.llmRequestFailed("Unknown error after \(maxRetries) retries")
    }

    /// Parse the raw JSON response data from an LLM API call.
    /// Handles both standard content and reasoning model fallbacks.
    private func parseLLMResponse(data: Data) throws -> String {
        let rawResponse = String(data: data, encoding: .utf8) ?? "<binary data>"
        Log.Agent.debug("callLLM: Raw JSON response (first 500 chars): \(String(rawResponse.prefix(500)))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            Log.Agent.error("callLLM: Failed to parse JSON structure. Raw: \(rawResponse)")
            throw AgentError.invalidLLMResponse("Could not parse response")
        }

        let finishReason = firstChoice["finish_reason"] as? String ?? "unknown"
        if finishReason == "length" {
            Log.Agent.warning("callLLM: Response truncated (finish_reason=length)")

            if message["content"] == nil || (message["content"] as? String) == nil {
                Log.Agent.debug("callLLM: Truncated response with no content - will retry")
                throw AgentError.invalidLLMResponse("Response truncated before generating action (finish_reason=length)")
            }
        }

        if let content = message["content"] as? String {
            return content
        }

        // Content is null - try reasoning_content as fallback
        if let reasoningContent = message["reasoning_content"] as? String {
            Log.Agent.warning("callLLM: content is null, using reasoning_content as fallback")

            if reasoningContent.range(of: "THOUGHT:", options: .caseInsensitive) != nil &&
               reasoningContent.range(of: "ACTION:", options: .caseInsensitive) != nil {
                Log.Agent.debug("callLLM: reasoning_content contains THOUGHT/ACTION markers, using it")
                return reasoningContent
            }

            if let extractedAction = AgentReasoningExtractor.extract(from: reasoningContent) {
                Log.Agent.debug("callLLM: Extracted action from reasoning_content: \(extractedAction)")
                return "THOUGHT: (extracted from reasoning)\nACTION: \(extractedAction)"
            }

            Log.Agent.debug("callLLM: reasoning_content lacks markers and no action extractable")
            throw AgentError.invalidLLMResponse("Model returned only reasoning_content without actionable output")
        }

        Log.Agent.error("callLLM: Both content and reasoning_content are null (finish_reason: \(finishReason))")
        throw AgentError.invalidLLMResponse("No content in response (finish_reason: \(finishReason))")
    }
}
