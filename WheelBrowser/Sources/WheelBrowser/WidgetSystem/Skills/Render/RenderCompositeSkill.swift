import Foundation

/// Converts pipeline data into a `RenderInput.composite` layout of child widgets.
struct RenderCompositeSkill: WidgetSkill {
    let name = SkillName.renderComposite

    let paramSchema = """
    {
      "layout": "string (required) — one of: vstack, hstack, grid_2col",
      "children": "array (required) — array of render skill specs, each with {skill, params}",
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
        for childSpec in childSpecs {
            guard let skillRaw = childSpec["skill"] as? String,
                  let skill = SkillName(rawValue: skillRaw),
                  skill.isRenderSkill else {
                continue
            }

            var childParams = (childSpec["params"] as? [String: Any]) ?? [:]
            // Inject the parent's input if the child doesn't have its own
            if childParams["input"] == nil {
                childParams["input"] = input
            }

            let renderSkill = renderSkillFor(skill)
            let result = try await renderSkill.execute(params: childParams)
            if let renderInput = result as? RenderInput {
                children.append(renderInput)
            }
        }

        return RenderInput.composite(layout: layout, children: children)
    }

    private func renderSkillFor(_ skill: SkillName) -> any WidgetSkill {
        switch skill {
        case .renderList: return RenderListSkill()
        case .renderStatCard: return RenderStatCardSkill()
        case .renderChart: return RenderChartSkill()
        case .renderTable: return RenderTableSkill()
        default: return RenderListSkill()
        }
    }
}
