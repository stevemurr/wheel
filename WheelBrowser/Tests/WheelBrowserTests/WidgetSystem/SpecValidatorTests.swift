import Testing
import Foundation
@testable import WheelBrowser

@Suite("SpecValidator")
struct SpecValidatorTests {

    private func makeSpec(
        title: String = "Test",
        refreshInterval: Int = 600,
        pipeline: [PipelineStep]
    ) -> WidgetPipelineSpec {
        WidgetPipelineSpec(
            title: title,
            refreshIntervalSeconds: refreshInterval,
            pipeline: pipeline
        )
    }

    // MARK: - Valid Specs

    @Test("Valid spec passes all checks")
    func validSpec() throws {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "fetch", skill: .fetchRedditPosts, params: ["subreddit": AnyCodable("swift")]),
            PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{fetch.output}}")]),
        ])
        let validated = try SpecValidator.validate(spec)
        #expect(validated.spec.title == "Test")
    }

    @Test("Single render step is valid")
    func singleRenderStep() throws {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "render", skill: .renderStatCard, params: ["label": AnyCodable("Value")]),
        ])
        _ = try SpecValidator.validate(spec)
    }

    // MARK: - Pass 1: Schema

    @Test("Pass 1: Duplicate step IDs")
    func duplicateStepIds() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "step", skill: .fetchRedditPosts, params: [:]),
            PipelineStep(id: "step", skill: .renderList, params: [:]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 1: Empty step ID")
    func emptyStepId() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "", skill: .renderList, params: [:]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    // MARK: - Pass 2: References

    @Test("Pass 2: Reference to nonexistent step")
    func badReference() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{missing.output}}")]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 2: Forward reference fails")
    func forwardReference() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "sort", skill: .sort, params: ["input": AnyCodable("{{fetch.output}}")]),
            PipelineStep(id: "fetch", skill: .fetchRedditPosts, params: [:]),
            PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{sort.output}}")]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    // MARK: - Pass 3: Last Step Is Render

    @Test("Pass 3: Last step not a render skill")
    func lastStepNotRender() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "fetch", skill: .fetchRedditPosts, params: [:]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 3: Empty pipeline")
    func emptyPipeline() {
        let spec = makeSpec(pipeline: [])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    // MARK: - Pass 4: URL Allowlist

    @Test("Pass 4: Disallowed domain")
    func disallowedDomain() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "fetch", skill: .fetchRestApi, params: ["url": AnyCodable("https://evil.com/data")]),
            PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{fetch.output}}")]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 4: HTTP (not HTTPS) rejected")
    func httpRejected() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "fetch", skill: .fetchRestApi, params: ["url": AnyCodable("http://api.github.com/repos")]),
            PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{fetch.output}}")]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 4: Allowed domain passes")
    func allowedDomain() throws {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "fetch", skill: .fetchRestApi, params: ["url": AnyCodable("https://api.github.com/repos")]),
            PipelineStep(id: "render", skill: .renderList, params: ["input": AnyCodable("{{fetch.output}}")]),
        ])
        _ = try SpecValidator.validate(spec)
    }

    // MARK: - Pass 5: Resource Limits

    @Test("Pass 5: Too many steps (6)")
    func tooManySteps() {
        let steps = (0..<5).map { PipelineStep(id: "s\($0)", skill: .sort, params: [:]) }
            + [PipelineStep(id: "render", skill: .renderList, params: [:])]
        let spec = makeSpec(pipeline: steps)
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 5: Too many fetch skills (4)")
    func tooManyFetches() {
        let spec = makeSpec(pipeline: [
            PipelineStep(id: "f1", skill: .fetchRedditPosts, params: [:]),
            PipelineStep(id: "f2", skill: .fetchCryptoPrice, params: [:]),
            PipelineStep(id: "f3", skill: .fetchWeather, params: [:]),
            PipelineStep(id: "f4", skill: .fetchRestApi, params: ["url": AnyCodable("https://api.github.com/x")]),
            PipelineStep(id: "render", skill: .renderList, params: [:]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }

    @Test("Pass 5: Refresh interval too low")
    func refreshTooLow() {
        let spec = makeSpec(refreshInterval: 60, pipeline: [
            PipelineStep(id: "render", skill: .renderList, params: [:]),
        ])
        #expect(throws: SpecValidationError.self) {
            try SpecValidator.validate(spec)
        }
    }
}
