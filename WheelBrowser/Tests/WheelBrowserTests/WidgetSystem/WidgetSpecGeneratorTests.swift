import Testing
import Foundation
@testable import WheelBrowser

/// Mock LLM client that returns canned responses for testing.
/// Thread-safe: all state set at init time, only callIndex mutates (protected by lock).
private final class WidgetMockLLMClient: LLMClient, @unchecked Sendable {
    private let responses: [String]
    private let lock = NSLock()
    private var callIndex = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func complete(messages: [ChatMessage], systemPrompt: String?, options: LLMRequestOptions) async throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard callIndex < responses.count else {
            throw LLMClientError.invalidResponse
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, options: LLMRequestOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: LLMClientError.invalidResponse) }
    }
}

@Suite("WidgetSpecGenerator")
struct WidgetSpecGeneratorTests {

    private static let validJSON = """
    {
        "title": "Test Widget",
        "refresh_interval_seconds": 600,
        "pipeline": [
            {"id": "fetch", "skill": "fetch_reddit_posts", "params": {"subreddit": "swift"}},
            {"id": "render", "skill": "render_list", "params": {"input": "{{fetch.output}}", "headline_field": "title"}}
        ]
    }
    """

    @Test("Successful generation")
    func successfulGeneration() async throws {
        let client = WidgetMockLLMClient(responses: [Self.validJSON])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        let result = try await generator.generate(prompt: "Show top swift posts", model: "test-model")
        #expect(result.spec.title == "Test Widget")
        #expect(result.spec.pipeline.count == 2)
    }

    @Test("Repair loop on invalid JSON, then valid")
    func repairLoop() async throws {
        let client = WidgetMockLLMClient(responses: [
            "This is not valid JSON at all",
            Self.validJSON,
        ])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        let result = try await generator.generate(prompt: "Show posts", model: "test-model")
        #expect(result.spec.title == "Test Widget")
    }

    @Test("Exhausted repair attempts")
    func exhaustedRepairs() async {
        let client = WidgetMockLLMClient(responses: [
            "not json",
            "still not json",
            "nope",
        ])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        do {
            _ = try await generator.generate(prompt: "Generate", model: "test-model")
            Issue.record("Expected error")
        } catch let error as WidgetError {
            if case .specGenerationFailed = error {
                // Expected
            } else {
                Issue.record("Wrong error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Strip markdown fences")
    func stripMarkdownFences() async throws {
        let client = WidgetMockLLMClient(responses: ["```json\n\(Self.validJSON)\n```"])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        let result = try await generator.generate(prompt: "Show posts", model: "test-model")
        #expect(result.spec.title == "Test Widget")
    }

    @Test("Validation error triggers repair")
    func validationRepair() async throws {
        let invalidSpec = """
        {
            "title": "Bad",
            "refresh_interval_seconds": 10,
            "pipeline": [
                {"id": "render", "skill": "render_list", "params": {}}
            ]
        }
        """

        let client = WidgetMockLLMClient(responses: [invalidSpec, Self.validJSON])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        let result = try await generator.generate(prompt: "Show data", model: "test-model")
        #expect(result.spec.refreshIntervalSeconds == 600)
    }

    // MARK: - Additional Generator Tests

    @Test("LLM error propagation: client throws, generator throws")
    func llmErrorPropagation() async {
        let client = WidgetErrorLLMClient()
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        do {
            _ = try await generator.generate(prompt: "fail", model: "test-model")
            Issue.record("Expected error")
        } catch let error as WidgetError {
            if case .specGenerationFailed(let msg) = error {
                #expect(msg.contains("LLM request failed"))
            } else {
                Issue.record("Wrong WidgetError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Triple-backtick markdown fences with json language tag")
    func tripleBacktickWithJsonTag() async throws {
        let wrappedJSON = "```json\n\(Self.validJSON)\n```"
        let client = WidgetMockLLMClient(responses: [wrappedJSON])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        let result = try await generator.generate(prompt: "Generate", model: "test-model")
        #expect(result.spec.title == "Test Widget")
    }

    @Test("Non-spec JSON (valid JSON but wrong structure)")
    func nonSpecJSON() async {
        let badStructure = """
        {"name": "not a widget spec", "data": [1, 2, 3]}
        """
        let client = WidgetMockLLMClient(responses: [
            badStructure,
            badStructure,
            badStructure,
        ])
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        do {
            _ = try await generator.generate(prompt: "Generate", model: "test-model")
            Issue.record("Expected error")
        } catch {
            // Expected: should fail because structure doesn't match WidgetPipelineSpec
        }
    }

    @Test("Model passthrough: mock client receives correct model")
    func modelPassthrough() async throws {
        let client = WidgetModelCaptureLLMClient(response: Self.validJSON)
        let registry = SkillRegistry.createDefault()
        let generator = WidgetSpecGenerator(llmClient: client, registry: registry)

        _ = try await generator.generate(prompt: "Generate", model: "test-model")
        #expect(client.capturedModel == "test-model")
    }
}

/// Mock LLM client that always throws an error.
private final class WidgetErrorLLMClient: LLMClient, @unchecked Sendable {
    func complete(messages: [ChatMessage], systemPrompt: String?, options: LLMRequestOptions) async throws -> String {
        throw LLMClientError.invalidResponse
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, options: LLMRequestOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: LLMClientError.invalidResponse) }
    }
}

/// Mock LLM client that captures the model parameter from options.
private final class WidgetModelCaptureLLMClient: LLMClient, @unchecked Sendable {
    private let response: String
    private(set) var capturedModel: String?

    init(response: String) {
        self.response = response
    }

    func complete(messages: [ChatMessage], systemPrompt: String?, options: LLMRequestOptions) async throws -> String {
        capturedModel = options.model
        return response
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, options: LLMRequestOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: LLMClientError.invalidResponse) }
    }
}
