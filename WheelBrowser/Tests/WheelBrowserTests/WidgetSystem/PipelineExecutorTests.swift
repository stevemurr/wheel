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
}
