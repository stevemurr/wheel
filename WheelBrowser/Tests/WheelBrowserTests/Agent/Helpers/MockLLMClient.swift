import Foundation
@testable import WheelBrowser

/// Mock LLM client that returns scripted responses for deterministic unit testing.
///
/// Usage:
/// ```swift
/// let mock = MockLLMClient(responses: [
///     "THOUGHT: I see a search box.\nACTION: type(1, \"hello\")",
///     "THOUGHT: Typed the text, now press enter.\nACTION: press_enter",
///     "THOUGHT: Results are showing.\nACTION: done(\"Search complete\")"
/// ])
/// let engine = AgentEngine(browserState: state, llmClient: mock, bridgeProvider: provider)
/// ```
@MainActor
final class MockLLMClient: AgentStreamingLLMClient {
    /// Scripted responses returned in order
    private var responses: [String]
    /// Index of the next response to return
    private var callIndex = 0
    /// Record of all prompts sent
    private(set) var promptHistory: [(prompt: String, systemPrompt: String)] = []
    /// When true, streamLLM yields tokens one character at a time; otherwise yields the full response as one chunk
    var simulateStreaming: Bool = false

    init(responses: [String]) {
        self.responses = responses
    }

    nonisolated func callLLM(prompt: String, systemPrompt: String) async throws -> String {
        return await MainActor.run {
            promptHistory.append((prompt: prompt, systemPrompt: systemPrompt))

            guard callIndex < responses.count else {
                // Return done() to prevent infinite loops
                return "THOUGHT: No more scripted responses.\nACTION: done(\"Mock ran out of responses\")"
            }

            let response = responses[callIndex]
            callIndex += 1
            return response
        }
    }

    nonisolated func streamLLM(prompt: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                self.promptHistory.append((prompt: prompt, systemPrompt: systemPrompt))

                guard self.callIndex < self.responses.count else {
                    let fallback = "THOUGHT: No more scripted responses.\nACTION: done(\"Mock ran out of responses\")"
                    continuation.yield(fallback)
                    continuation.finish()
                    return
                }

                let response = self.responses[self.callIndex]
                self.callIndex += 1

                if self.simulateStreaming {
                    for char in response {
                        continuation.yield(String(char))
                    }
                } else {
                    continuation.yield(response)
                }
                continuation.finish()
            }
        }
    }
}
