import Testing
import Foundation
@testable import WheelBrowser

/// Creates a WidgetSpecGenerator with a mock completion provider that returns canned responses.
private func makeGenerator(responses: [String]) -> WidgetSpecGenerator {
    let lock = NSLock()
    var callIndex = 0

    let provider: WidgetSpecGenerator.CompletionProvider = { _, _ in
        lock.lock()
        defer { lock.unlock() }

        guard callIndex < responses.count else {
            throw OnDeviceLLMError.modelUnavailable("Mock ran out of responses")
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }

    return WidgetSpecGenerator(
        registry: SkillRegistry.createDefault(),
        completionProvider: provider
    )
}

/// Creates a WidgetSpecGenerator with a mock that always throws.
private func makeErrorGenerator() -> WidgetSpecGenerator {
    let provider: WidgetSpecGenerator.CompletionProvider = { _, _ in
        throw OnDeviceLLMError.modelUnavailable("Test error")
    }

    return WidgetSpecGenerator(
        registry: SkillRegistry.createDefault(),
        completionProvider: provider
    )
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
        let generator = makeGenerator(responses: [Self.validJSON])

        let result = try await generator.generate(prompt: "Show top swift posts")
        #expect(result.spec.title == "Test Widget")
        #expect(result.spec.pipeline.count == 2)
    }

    @Test("Repair loop on invalid JSON, then valid")
    func repairLoop() async throws {
        let generator = makeGenerator(responses: [
            "This is not valid JSON at all",
            Self.validJSON,
        ])

        let result = try await generator.generate(prompt: "Show posts")
        #expect(result.spec.title == "Test Widget")
    }

    @Test("Exhausted repair attempts")
    func exhaustedRepairs() async {
        let generator = makeGenerator(responses: [
            "not json",
            "still not json",
            "nope",
        ])

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
        let generator = makeGenerator(responses: ["```json\n\(Self.validJSON)\n```"])

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

        let generator = makeGenerator(responses: [invalidSpec, Self.validJSON])

        let result = try await generator.generate(prompt: "Show data")
        #expect(result.spec.refreshIntervalSeconds == 600)
    }

    // MARK: - Additional Generator Tests

    @Test("LLM error propagation: client throws, generator throws")
    func llmErrorPropagation() async {
        let generator = makeErrorGenerator()

        do {
            _ = try await generator.generate(prompt: "fail")
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
        let generator = makeGenerator(responses: [wrappedJSON])

        let result = try await generator.generate(prompt: "Generate")
        #expect(result.spec.title == "Test Widget")
    }

    @Test("Non-spec JSON (valid JSON but wrong structure)")
    func nonSpecJSON() async {
        let badStructure = """
        {"name": "not a widget spec", "data": [1, 2, 3]}
        """
        let generator = makeGenerator(responses: [
            badStructure,
            badStructure,
            badStructure,
        ])

        do {
            _ = try await generator.generate(prompt: "Generate")
            Issue.record("Expected error")
        } catch {
            // Expected: should fail because structure doesn't match WidgetPipelineSpec
        }
    }
}
