import Testing
import Foundation
import FoundationModels
@testable import WheelBrowser

private actor StructuredResponseQueue {
    private var responses: [GeneratedWidgetPipelineSpec]
    private var callIndex = 0

    init(responses: [GeneratedWidgetPipelineSpec]) {
        self.responses = responses
    }

    func next() throws -> GeneratedWidgetPipelineSpec {
        guard callIndex < responses.count else {
            throw OnDeviceLLMError.modelUnavailable("Mock ran out of responses")
        }

        let response = responses[callIndex]
        callIndex += 1
        return response
    }
}

private func object(_ properties: [String: GeneratedContent]) -> GeneratedContent {
    GeneratedContent(kind: .structure(properties: properties, orderedKeys: properties.keys.sorted()))
}

private func string(_ value: String) -> GeneratedContent {
    GeneratedContent(kind: .string(value))
}

/// Creates a WidgetSpecGenerator with a mock completion provider that returns canned structured responses.
private func makeGenerator(responses: [GeneratedWidgetPipelineSpec]) -> WidgetSpecGenerator {
    let queue = StructuredResponseQueue(responses: responses)

    let provider: WidgetSpecGenerator.CompletionProvider = { _, _ in
        try await queue.next()
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

    private static let validResponse = GeneratedWidgetPipelineSpec(
        title: "Test Widget",
        refreshIntervalSeconds: 600,
        pipeline: [
            GeneratedWidgetPipelineStep(
                id: "fetch",
                skill: "fetch_reddit_posts",
                params: object(["subreddit": string("swift")])
            ),
            GeneratedWidgetPipelineStep(
                id: "render",
                skill: "render_list",
                params: object([
                    "input": string("{{fetch.output}}"),
                    "headline_field": string("title")
                ])
            )
        ],
        thinking: nil
    )

    private static let invalidStructuredResponse = GeneratedWidgetPipelineSpec(
        title: "Broken Widget",
        refreshIntervalSeconds: 600,
        pipeline: [
            GeneratedWidgetPipelineStep(
                id: "fetch",
                skill: "not_a_real_skill",
                params: object(["subreddit": string("swift")])
            )
        ],
        thinking: nil
    )

    @Test("Successful generation")
    func successfulGeneration() async throws {
        let generator = makeGenerator(responses: [Self.validResponse])

        let result = try await generator.generate(prompt: "Show top swift posts")
        #expect(result.spec.title == "Test Widget")
        #expect(result.spec.pipeline.count == 2)
    }

    @Test("Repair loop on invalid structured response, then valid")
    func repairLoop() async throws {
        let generator = makeGenerator(responses: [
            Self.invalidStructuredResponse,
            Self.validResponse,
        ])

        let result = try await generator.generate(prompt: "Show posts")
        #expect(result.spec.title == "Test Widget")
    }

    @Test("Exhausted repair attempts")
    func exhaustedRepairs() async {
        let generator = makeGenerator(responses: [
            Self.invalidStructuredResponse,
            Self.invalidStructuredResponse,
            Self.invalidStructuredResponse,
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

    @Test("Validation error triggers repair")
    func validationRepair() async throws {
        let invalidSpec = GeneratedWidgetPipelineSpec(
            title: "Bad",
            refreshIntervalSeconds: 10,
            pipeline: [
                GeneratedWidgetPipelineStep(
                    id: "render",
                    skill: "render_list",
                    params: object([:])
                )
            ],
            thinking: nil
        )

        let generator = makeGenerator(responses: [invalidSpec, Self.validResponse])

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
}
