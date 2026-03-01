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
final class MockLLMClient: LLMClient {
    /// Scripted responses returned in order
    private var responses: [String]
    /// Index of the next response to return
    private var callIndex = 0
    /// Record of all prompts sent
    private(set) var promptHistory: [(prompt: String, systemPrompt: String)] = []

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
}
