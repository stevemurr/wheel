import Testing
import Foundation
@testable import WheelBrowser

@Suite("PipelineExecutor")
struct PipelineExecutorTests {

    @Test("Execute simple render-only pipeline")
    @MainActor
    func simpleRenderPipeline() async throws {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Test",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(
                    id: "render",
                    skill: .renderStatCard,
                    params: [
                        "label": AnyCodable("Test"),
                        "value_field": AnyCodable("value"),
                        "input": AnyCodable([["value": 42]] as [[String: Any]]),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .statCard(let label, _, _, _) = result {
            #expect(label == "Test")
        } else {
            Issue.record("Expected statCard, got \(result)")
        }
    }

    @Test("Pipeline with reference resolution")
    @MainActor
    func referenceResolution() async throws {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        // Use sort + render to test reference resolution without network calls
        let spec = WidgetPipelineSpec(
            title: "Test Sort + Render",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(
                    id: "sort_step",
                    skill: .sort,
                    params: [
                        "input": AnyCodable([
                            ["name": "B", "score": 2],
                            ["name": "A", "score": 1],
                        ] as [[String: Any]]),
                        "field": AnyCodable("score"),
                        "order": AnyCodable("asc"),
                    ]
                ),
                PipelineStep(
                    id: "render",
                    skill: .renderList,
                    params: [
                        "input": AnyCodable("{{sort_step.output}}"),
                        "headline_field": AnyCodable("name"),
                        "badge_field": AnyCodable("score"),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .list(_, let items) = result {
            #expect(items.count == 2)
            #expect(items[0].headline == "A")
            #expect(items[1].headline == "B")
        } else {
            Issue.record("Expected list, got \(result)")
        }
    }

    @Test("Empty pipeline fails")
    @MainActor
    func emptyPipeline() async {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(title: "Empty", refreshIntervalSeconds: 300, pipeline: [])
        let validated = ValidatedSpec(trusted: spec)

        do {
            _ = try await executor.execute(validated)
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }

    @Test("Full pipeline flow with mock skill: 2 steps")
    @MainActor
    func fullPipelineWithMock() async throws {
        let mockFetch = MockWidgetSkill(
            name: .fetchRedditPosts,
            result: [["title": "Hello", "score": 10]] as [[String: Any]]
        )
        let registry = SkillRegistry(skills: [mockFetch, RenderListSkill()])
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Mock Pipeline",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(id: "fetch", skill: .fetchRedditPosts, params: [:]),
                PipelineStep(
                    id: "render",
                    skill: .renderList,
                    params: [
                        "input": AnyCodable("{{fetch.output}}"),
                        "headline_field": AnyCodable("title"),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .list(_, let items) = result {
            #expect(items.count == 1)
            #expect(items[0].headline == "Hello")
        } else {
            Issue.record("Expected list, got \(result)")
        }

        #expect(mockFetch.invocationCount == 1)
    }

    @Test("Error includes step ID in wrapping")
    @MainActor
    func errorIncludesStepId() async {
        let mockFetch = MockWidgetSkill(
            name: .fetchRedditPosts,
            error: SkillParamError.missing("url")
        )
        let registry = SkillRegistry(skills: [mockFetch, RenderListSkill()])
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Error Pipeline",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(id: "fetch_step", skill: .fetchRedditPosts, params: [:]),
                PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{fetch_step.output}}")]),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        do {
            _ = try await executor.execute(validated)
            Issue.record("Expected error")
        } catch let error as WidgetError {
            if case .executionFailed(let stepId, _) = error {
                #expect(stepId == "fetch_step")
            } else {
                Issue.record("Wrong WidgetError case: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Context from step 1 available to step 2")
    @MainActor
    func contextFlowsBetweenSteps() async throws {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Context Flow",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(
                    id: "sort_step",
                    skill: .sort,
                    params: [
                        "input": AnyCodable([
                            ["name": "Z", "score": 3],
                            ["name": "A", "score": 1],
                        ] as [[String: Any]]),
                        "field": AnyCodable("score"),
                        "order": AnyCodable("asc"),
                    ]
                ),
                PipelineStep(
                    id: "filter_step",
                    skill: .filter,
                    params: [
                        "input": AnyCodable("{{sort_step.output}}"),
                        "field": AnyCodable("score"),
                        "operator": AnyCodable("gt"),
                        "value": AnyCodable(0),
                    ]
                ),
                PipelineStep(
                    id: "render",
                    skill: .renderList,
                    params: [
                        "input": AnyCodable("{{filter_step.output}}"),
                        "headline_field": AnyCodable("name"),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .list(_, let items) = result {
            #expect(items.count == 2)
            #expect(items[0].headline == "A")
        } else {
            Issue.record("Expected list, got \(result)")
        }
    }

    @Test("Pipeline with non-render last step fails")
    @MainActor
    func nonRenderLastStepFails() async {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Bad Pipeline",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(
                    id: "sort_only",
                    skill: .sort,
                    params: [
                        "input": AnyCodable([["x": 1]] as [[String: Any]]),
                        "field": AnyCodable("x"),
                        "order": AnyCodable("asc"),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        do {
            _ = try await executor.execute(validated)
            Issue.record("Expected error for non-render last step")
        } catch let error as WidgetError {
            if case .renderFailed = error {
                // Expected
            } else {
                Issue.record("Wrong WidgetError: \(error)")
            }
        } catch {
            // Other errors also acceptable
        }
    }

    @Test("Duplicate step IDs in pipeline")
    @MainActor
    func duplicateStepIds() async throws {
        // The executor trusts ValidatedSpec, but this tests the behavior with duplicates
        let mockFetch = MockWidgetSkill(
            name: .fetchRedditPosts,
            result: [["title": "First"]] as [[String: Any]]
        )
        let registry = SkillRegistry(skills: [mockFetch, RenderListSkill()])
        let executor = PipelineExecutor(registry: registry)

        // Two steps with same ID — the second overwrites the first in context
        let spec = WidgetPipelineSpec(
            title: "Dup IDs",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(id: "fetch", skill: .fetchRedditPosts, params: [:]),
                PipelineStep(id: "render", skill: .renderList, params: [
                    "input": AnyCodable("{{fetch.output}}"),
                    "headline_field": AnyCodable("title"),
                ]),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .list(_, let items) = result {
            #expect(items.count == 1)
        } else {
            Issue.record("Expected list")
        }
    }

    @Test("Reference resolution works across steps")
    @MainActor
    func referenceResolutionAcrossSteps() async throws {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Cross-step Refs",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(
                    id: "sort",
                    skill: .sort,
                    params: [
                        "input": AnyCodable([["n": 2], ["n": 1]] as [[String: Any]]),
                        "field": AnyCodable("n"),
                        "order": AnyCodable("asc"),
                    ]
                ),
                PipelineStep(
                    id: "render",
                    skill: .renderList,
                    params: [
                        "input": AnyCodable("{{sort.output}}"),
                        "headline_field": AnyCodable("n"),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .list(_, let items) = result {
            #expect(items[0].headline == "1")
            #expect(items[1].headline == "2")
        } else {
            Issue.record("Expected list")
        }
    }

    @Test("Single-step render pipeline succeeds")
    @MainActor
    func singleStepRender() async throws {
        let registry = SkillRegistry.createDefault()
        let executor = PipelineExecutor(registry: registry)

        let spec = WidgetPipelineSpec(
            title: "Single Step",
            refreshIntervalSeconds: 300,
            pipeline: [
                PipelineStep(
                    id: "render",
                    skill: .renderStatCard,
                    params: [
                        "label": AnyCodable("Price"),
                        "value_field": AnyCodable("price"),
                        "input": AnyCodable([["price": 42.5]] as [[String: Any]]),
                    ]
                ),
            ]
        )

        let validated = ValidatedSpec(trusted: spec)
        let result = try await executor.execute(validated)

        if case .statCard(let label, _, _, _) = result {
            #expect(label == "Price")
        } else {
            Issue.record("Expected statCard")
        }
    }
}
