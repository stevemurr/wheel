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

        let result = try await generator.generate(prompt: "Show top swift posts")
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

        let result = try await generator.generate(prompt: "Show posts")
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
            _ = try await generator.generate(prompt: "Generate")
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

        let result = try await generator.generate(prompt: "Show posts")
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

        let result = try await generator.generate(prompt: "Show data")
        #expect(result.spec.refreshIntervalSeconds == 600)
    }
}
