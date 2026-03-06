import Foundation
import FoundationModels

@Generable(description: "A complete widget pipeline specification.")
struct GeneratedWidgetPipelineSpec: Sendable {
    let title: String
    let refreshIntervalSeconds: Int
    let pipeline: [GeneratedWidgetPipelineStep]
    let thinking: String?

    init(title: String, refreshIntervalSeconds: Int, pipeline: [GeneratedWidgetPipelineStep], thinking: String?) {
        self.title = title
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.pipeline = pipeline
        self.thinking = thinking
    }

    func toWidgetPipelineSpec(widgetId: UUID = UUID()) throws -> WidgetPipelineSpec {
        let steps = try pipeline.map { try $0.toPipelineStep() }

        return WidgetPipelineSpec(
            title: title,
            refreshIntervalSeconds: refreshIntervalSeconds,
            pipeline: steps,
            widgetId: widgetId,
            thinking: thinking
        )
    }
}

@Generable(description: "A single widget pipeline step.")
struct GeneratedWidgetPipelineStep: Sendable {
    let id: String
    let skill: String
    let params: GeneratedContent

    init(id: String, skill: String, params: GeneratedContent) {
        self.id = id
        self.skill = skill
        self.params = params
    }

    func toPipelineStep() throws -> PipelineStep {
        guard let skillName = SkillName(rawValue: skill) else {
            throw WidgetError.unknownSkill(skill)
        }

        return PipelineStep(
            id: id,
            skill: skillName,
            params: try GeneratedContentBridge.anyCodableDictionary(from: params)
        )
    }
}
