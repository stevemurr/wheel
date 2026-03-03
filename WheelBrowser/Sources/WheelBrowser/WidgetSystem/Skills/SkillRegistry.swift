import Foundation

/// Central registry of all available pipeline skills.
/// Skills are registered at startup and looked up by name during pipeline execution.
final class SkillRegistry: Sendable {
    private let skills: [SkillName: any WidgetSkill]

    init(skills: [any WidgetSkill]) {
        var map: [SkillName: any WidgetSkill] = [:]
        for skill in skills {
            map[skill.name] = skill
        }
        self.skills = map
    }

    /// Create a registry with all built-in skills.
    static func createDefault() -> SkillRegistry {
        let sandbox = TransformSandbox()
        return SkillRegistry(skills: [
            // Acquisition
            FetchRedditSkill(),
            FetchCryptoPriceSkill(),
            FetchWeatherSkill(),
            FetchRestApiSkill(),
            // Transform
            SortSkill(sandbox: sandbox),
            FilterSkill(sandbox: sandbox),
            MapFieldsSkill(sandbox: sandbox),
            AggregateSkill(sandbox: sandbox),
            // Render
            RenderListSkill(),
            RenderStatCardSkill(),
            RenderChartSkill(),
            RenderTableSkill(),
            RenderCompositeSkill(),
        ])
    }

    /// Look up and execute a skill by name.
    func execute(skill: SkillName, params: [String: Any]) async throws -> Any {
        guard let impl = skills[skill] else {
            throw WidgetError.unknownSkill(skill.rawValue)
        }
        return try await impl.execute(params: params)
    }

    /// Generate a system prompt fragment listing all available skills and their param schemas.
    func systemPromptRegistry() -> String {
        var lines: [String] = ["Available skills:"]
        for skillName in SkillName.allCases {
            guard let skill = skills[skillName] else { continue }
            lines.append("")
            lines.append("### \(skillName.rawValue)")
            lines.append(skill.paramSchema)
        }
        return lines.joined(separator: "\n")
    }
}
