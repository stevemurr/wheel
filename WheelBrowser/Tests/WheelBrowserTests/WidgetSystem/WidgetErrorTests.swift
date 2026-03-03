import Testing
import Foundation
@testable import WheelBrowser

@Suite("WidgetError")
struct WidgetErrorTests {

    @Test("unknownSkill has description")
    func unknownSkillDescription() {
        let error = WidgetError.unknownSkill("nonexistent_skill")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("nonexistent_skill"))
    }

    @Test("invalidReference has description with step and ref")
    func invalidReferenceDescription() {
        let error = WidgetError.invalidReference(stepId: "step_2", ref: "missing_step")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("step_2"))
        #expect(error.errorDescription!.contains("missing_step"))
    }

    @Test("validationFailed has description with pass number")
    func validationFailedDescription() {
        let validationError = SpecValidationError(pass: 3, stepIndex: 1, message: "bad step", suggestion: "fix it")
        let error = WidgetError.validationFailed(validationError)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("3"))
    }

    @Test("executionFailed wraps underlying error")
    func executionFailedDescription() {
        let underlying = SkillParamError.missing("url")
        let error = WidgetError.executionFailed(stepId: "fetch", underlying: underlying)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("fetch"))
    }

    @Test("renderFailed has description")
    func renderFailedDescription() {
        let error = WidgetError.renderFailed("chart rendering failed")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("chart rendering failed"))
    }

    @Test("specGenerationFailed has description")
    func specGenerationFailedDescription() {
        let error = WidgetError.specGenerationFailed("LLM returned empty")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("LLM returned empty"))
    }

    @Test("stepTimeout has description with step ID")
    func stepTimeoutDescription() {
        let error = WidgetError.stepTimeout(stepId: "slow_step")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("slow_step"))
        #expect(error.errorDescription!.contains("timed out"))
    }
}
