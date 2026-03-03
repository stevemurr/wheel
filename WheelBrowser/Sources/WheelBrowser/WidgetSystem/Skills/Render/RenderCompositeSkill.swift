import Foundation

/// Converts pipeline data into a `RenderInput.composite` layout of child widgets.
struct RenderCompositeSkill: WidgetSkill {
    let name = SkillName.renderComposite

    let paramSchema = """
    {
      "layout": "string (required) — one of: vstack, hstack, grid_2col",
      "children": "array of objects (required) — each child is a render spec: {\"skill\": \"<render_skill_name>\", \"params\": {<skill_params_without_input>}}. The parent's input is injected automatically if the child omits 'input'. Example: [{\"skill\": \"render_stat_card\", \"params\": {\"label\": \"Total\", \"value_field\": \"value\"}}, {\"skill\": \"render_chart\", \"params\": {\"chart_type\": \"bar\", \"x_field\": \"name\", \"y_field\": \"count\"}}]",
      "input": "reference (required) — {{step_id.output}} from a previous step"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        let layoutRaw = (params["layout"] as? String) ?? "vstack"
        let layout = CompositeLayout(rawValue: layoutRaw) ?? .vstack

        guard let childSpecs = params["children"] as? [[String: Any]] else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.missing("children"))
        }

        let input = params["input"]

        // Each child is a mini render spec with skill + params
        var children: [RenderInput] = []
        for (childIndex, childSpec) in childSpecs.enumerated() {
            guard let skillRaw = childSpec["skill"] as? String else {
                throw WidgetError.renderFailed("Composite child \(childIndex) is missing 'skill' key")
            }
            guard let skill = SkillName(rawValue: skillRaw), skill.isRenderSkill else {
                throw WidgetError.renderFailed("Composite child \(childIndex) has invalid render skill '\(skillRaw)'")
            }

            var childParams = (childSpec["params"] as? [String: Any]) ?? [:]
            // Inject the parent's input if the child doesn't have its own
            if childParams["input"] == nil {
                childParams["input"] = input
            }

            let renderSkill = renderSkillFor(skill)
            let result = try await renderSkill.execute(params: childParams)
            guard let renderInput = result as? RenderInput else {
                throw WidgetError.renderFailed("Composite child \(childIndex) (\(skillRaw)) did not produce a RenderInput")
            }
            children.append(renderInput)
        }

        return RenderInput.composite(layout: layout, children: children)
    }

    private func renderSkillFor(_ skill: SkillName) -> any WidgetSkill {
        switch skill {
        case .renderList: return RenderListSkill()
        case .renderStatCard: return RenderStatCardSkill()
        case .renderChart: return RenderChartSkill()
        case .renderTable: return RenderTableSkill()
        case .renderComposite: return RenderCompositeSkill()
        default: return RenderListSkill()
        }
    }
}
