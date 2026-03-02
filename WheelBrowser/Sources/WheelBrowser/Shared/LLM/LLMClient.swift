import Foundation

/// Protocol for unified LLM client interactions.
/// Abstracts away the specifics of different LLM APIs (OpenAI, Anthropic, local, etc.)
public protocol LLMClient: AnyObject, Sendable {
    /// Send a chat completion request and receive a complete response
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - systemPrompt: Optional system prompt to prepend
    ///   - options: Request configuration options
    /// - Returns: The assistant's response content
    func complete(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions
    ) async throws -> String

    /// Send a streaming chat completion request
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - systemPrompt: Optional system prompt to prepend
    ///   - options: Request configuration options
    /// - Returns: An async stream of response chunks
    func stream(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<String, Error>
}

/// Configuration options for LLM requests
public struct LLMRequestOptions: Sendable {
    /// Model identifier
    public var model: String

    /// Sampling temperature (0.0 - 2.0)
    public var temperature: Double

    /// Maximum tokens to generate
    public var maxTokens: Int

    /// Request timeout in seconds
    public var timeoutSeconds: TimeInterval

    public init(
        model: String = "gpt-4",
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        timeoutSeconds: TimeInterval = 120
    ) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
    }

    /// Default options for chat conversations
    public static let chat = LLMRequestOptions(temperature: 0.7, maxTokens: 2048)

    /// Options optimized for deterministic/factual responses
    public static let deterministic = LLMRequestOptions(temperature: 0.3, maxTokens: 2048)

    /// Options for agent/automation use cases
    public static let agent = LLMRequestOptions(temperature: 0.3, maxTokens: 1000)

    /// Options for creative/generation tasks
    public static let creative = LLMRequestOptions(temperature: 0.9, maxTokens: 4096)
}

/// Errors that can occur during LLM operations
public enum LLMClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case parseError(String)
    case notConfigured
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid LLM endpoint URL"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .parseError(let detail):
            return "Failed to parse LLM response: \(detail)"
        case .notConfigured:
            return "LLM endpoint not configured"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds"
            }
            return "Rate limited. Please try again later"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        }
    }

    /// Whether this error is transient and the request should be retried
    public var isRetryable: Bool {
        switch self {
        case .httpError(let code, _):
            return code >= 500 || code == 429
        case .rateLimited, .timeout:
            return true
        default:
            return false
        }
    }
}

// MARK: - OpenAI-Compatible Client Implementation

/// An LLM client implementation for OpenAI-compatible APIs
public final class OpenAICompatibleClient: LLMClient, @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession

    public init(baseURL: URL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = URLSession.shared
    }

    public func complete(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions
    ) async throws -> String {
        let request = try buildRequest(messages: messages, systemPrompt: systemPrompt, options: options, stream: false)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMClientError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return try parseCompletionResponse(data)
    }

    public func stream(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, systemPrompt: systemPrompt, options: options, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMClientError.invalidResponse
                    }

                    if httpResponse.statusCode != 200 {
                        throw LLMClientError.httpError(statusCode: httpResponse.statusCode, message: "Stream request failed")
                    }

                    // Parse SSE stream
                    for try await jsonString in bytes.sseEvents {
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions,
        stream: Bool
    ) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent("chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = options.timeoutSeconds

        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build messages array
        var apiMessages: [[String: String]] = []
        if let system = systemPrompt {
            apiMessages.append(["role": "system", "content": system])
        }
        apiMessages.append(contentsOf: messages.toAPIMessages())

        let body: [String: Any] = [
            "model": options.model,
            "messages": apiMessages,
            "temperature": options.temperature,
            "max_tokens": options.maxTokens,
            "stream": stream
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseCompletionResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMClientError.parseError("Could not extract content from response")
        }
        return content
    }
}

// MARK: - Retry Wrapper

/// A wrapper that adds automatic retry logic to any LLMClient
public final class RetryingLLMClient: LLMClient, @unchecked Sendable {
    private let wrapped: any LLMClient
    private let maxRetries: Int
    private let baseDelay: TimeInterval

    public init(
        wrapping client: any LLMClient,
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0
    ) {
        self.wrapped = client
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    public func complete(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions
    ) async throws -> String {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await wrapped.complete(messages: messages, systemPrompt: systemPrompt, options: options)
            } catch let error as LLMClientError where error.isRetryable {
                lastError = error
                if attempt < maxRetries {
                    let delay = baseDelay * pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? LLMClientError.invalidResponse
    }

    public func stream(
        messages: [ChatMessage],
        systemPrompt: String?,
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        // For streaming, we just delegate - retry logic is more complex
        // and typically handled at a higher level
        wrapped.stream(messages: messages, systemPrompt: systemPrompt, options: options)
    }
}
