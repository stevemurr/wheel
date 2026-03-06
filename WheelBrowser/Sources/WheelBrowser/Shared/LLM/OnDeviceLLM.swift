import Foundation
import FoundationModels

// MARK: - AgentLLMProvider Protocol

/// Protocol for agent LLM interactions, allowing test injection.
protocol AgentLLMProvider: Sendable {
    func complete(prompt: String, systemPrompt: String) async throws -> String
    func stream(prompt: String, systemPrompt: String) -> AsyncThrowingStream<String, Error>
}

// MARK: - OnDeviceLLM

/// Singleton service wrapping Apple's on-device FoundationModels framework.
/// Runs entirely on-device with zero configuration — no server, no API key, no network.
final class OnDeviceLLM: Sendable {
    static let shared = OnDeviceLLM()

    enum AvailabilityStatus: Equatable, Sendable {
        case available
        case unavailable(String)

        var isAvailable: Bool {
            if case .available = self {
                return true
            }
            return false
        }

        var reason: String? {
            if case .unavailable(let reason) = self {
                return reason
            }
            return nil
        }
    }

    /// Maximum token budget for the on-device model (input + output combined).
    private static let maxContextTokens = 4096
    /// Reserved tokens for model output.
    private static let outputReserve = 1000
    /// Approximate chars-per-token for budget estimation.
    private static let charsPerToken = 4

    private init() {}

    // MARK: - Availability

    /// Resolve model availability off the caller's actor to avoid blocking UI work.
    func availabilityStatus() async -> AvailabilityStatus {
        await Task.detached(priority: .utility) {
            Self.resolveAvailabilityStatus()
        }.value
    }

    private static func resolveAvailabilityStatus() -> AvailabilityStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac doesn't support Apple Intelligence. An Apple Silicon Mac is required.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is not enabled. Enable it in System Settings → Apple Intelligence & Siri.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device model is still downloading. Please wait and try again.")
        case .unavailable(_):
            return .unavailable("The on-device language model is not available on this device.")
        @unknown default:
            return .unavailable("The on-device language model is not available.")
        }
    }

    // MARK: - Completion

    /// Single-shot completion with conversation messages.
    func complete(messages: [ChatMessage], instructions: String) async throws -> String {
        let prompt = buildPrompt(from: pruneMessages(messages))
        return try await complete(prompt: prompt, instructions: instructions)
    }

    /// Single-shot completion with a raw prompt string.
    func complete(prompt: String, instructions: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let availability = Self.resolveAvailabilityStatus()
            guard availability.isAvailable else {
                throw OnDeviceLLMError.modelUnavailable(availability.reason ?? "Model not available")
            }

            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        }.value
    }

    /// Single-shot structured completion using FoundationModels guided generation.
    func complete<Content: Generable & Sendable>(
        prompt: String,
        instructions: String,
        generating type: Content.Type = Content.self
    ) async throws -> Content {
        try await Task.detached(priority: .userInitiated) {
            let availability = Self.resolveAvailabilityStatus()
            guard availability.isAvailable else {
                throw OnDeviceLLMError.modelUnavailable(availability.reason ?? "Model not available")
            }

            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: Content.self)
            return response.content
        }.value
    }

    // MARK: - Streaming

    /// Streaming completion with conversation messages.
    /// Yields incremental text deltas (not cumulative snapshots).
    func stream(messages: [ChatMessage], instructions: String) -> AsyncThrowingStream<String, Error> {
        let prompt = buildPrompt(from: pruneMessages(messages))
        return stream(prompt: prompt, instructions: instructions)
    }

    /// Streaming completion with a raw prompt string.
    func stream(prompt: String, instructions: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let availability = Self.resolveAvailabilityStatus()
                    guard availability.isAvailable else {
                        throw OnDeviceLLMError.modelUnavailable(availability.reason ?? "Model not available")
                    }

                    let session = LanguageModelSession(instructions: instructions)

                    var previousContent = ""
                    let stream = session.streamResponse(to: prompt)
                    for try await partialResponse in stream {
                        let currentContent = partialResponse.content
                        if currentContent.count > previousContent.count {
                            let delta = String(currentContent.dropFirst(previousContent.count))
                            continuation.yield(delta)
                            previousContent = currentContent
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Message Pruning

    /// Prunes messages to fit within the on-device model's token budget.
    /// Keeps the system message (if any) and as many recent messages as fit.
    func pruneMessages(_ messages: [ChatMessage], maxTokenBudget: Int? = nil) -> [ChatMessage] {
        let budget = maxTokenBudget ?? (Self.maxContextTokens - Self.outputReserve)
        let maxChars = budget * Self.charsPerToken

        var result: [ChatMessage] = []
        var totalChars = 0

        // Walk messages from most recent to oldest, accumulating until budget exceeded
        for message in messages.reversed() {
            let messageChars = message.content.count
            if totalChars + messageChars > maxChars && !result.isEmpty {
                break
            }
            result.insert(message, at: 0)
            totalChars += messageChars
        }

        return result
    }

    // MARK: - Prompt Building

    /// Converts ChatMessage array into a single prompt string for the model.
    private func buildPrompt(from messages: [ChatMessage]) -> String {
        messages.map { msg in
            switch msg.role {
            case .user:
                return "User: \(msg.content)"
            case .assistant:
                return "Assistant: \(msg.content)"
            case .system:
                return "System: \(msg.content)"
            case .thinking:
                return ""
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}

// MARK: - AgentLLMProvider Conformance

extension OnDeviceLLM: AgentLLMProvider {
    func complete(prompt: String, systemPrompt: String) async throws -> String {
        try await complete(prompt: prompt, instructions: systemPrompt)
    }

    func stream(prompt: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        stream(prompt: prompt, instructions: systemPrompt)
    }
}

// MARK: - Errors

enum OnDeviceLLMError: LocalizedError {
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return reason
        }
    }
}
