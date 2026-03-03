import Foundation

/// Validates a `WidgetPipelineSpec` through 5 sequential passes.
/// Returns a `ValidatedSpec` on success or throws `SpecValidationError` on failure.
enum SpecValidator {

    /// Run all validation passes and return a validated spec.
    static func validate(_ spec: WidgetPipelineSpec) throws -> ValidatedSpec {
        try pass1Schema(spec)
        try pass2References(spec)
        try pass3LastStepIsRender(spec)
        try pass4URLAllowlist(spec)
        try pass5ResourceLimits(spec)
        return ValidatedSpec(trusted: spec)
    }

    // MARK: - Pass 1: Schema Validation

    /// Required parameters for each skill. Catches the most common LLM omission errors.
    private static let requiredParams: [SkillName: [String]] = [
        .fetchRedditPosts: ["subreddit"],
        .fetchCryptoPrice: ["coin_id"],
        .fetchWeather: ["city"],
        .fetchRestApi: ["url"],
        .sort: ["field", "input"],
        .filter: ["field", "operator", "value", "input"],
        .mapFields: ["mapping", "input"],
        .aggregate: ["operation", "input"],
        .renderList: ["headline_field", "input"],
        .renderStatCard: ["label", "value_field", "input"],
        .renderChart: ["chart_type", "x_field", "y_field", "input"],
        .renderTable: ["columns", "input"],
        .renderComposite: ["layout", "children", "input"],
    ]

    /// Validates skill names are in the allowlist and required params are present.
    private static func pass1Schema(_ spec: WidgetPipelineSpec) throws {
        // Validate title constraints to match SpecSchema.json
        if spec.title.isEmpty {
            throw SpecValidationError(
                pass: 1,
                stepIndex: nil,
                message: "Title must not be empty.",
                suggestion: "Provide a human-readable title for the widget."
            )
        }
        if spec.title.count > 100 {
            throw SpecValidationError(
                pass: 1,
                stepIndex: nil,
                message: "Title is \(spec.title.count) characters, maximum is 100.",
                suggestion: "Shorten the widget title."
            )
        }

        for (index, step) in spec.pipeline.enumerated() {
            // Skill name is already validated by Codable parsing (it's an enum).
            // Validate step IDs are non-empty and alphanumeric.
            let validIdPattern = /^[a-z_][a-z0-9_]*$/
            if step.id.isEmpty || step.id.wholeMatch(of: validIdPattern) == nil {
                throw SpecValidationError(
                    pass: 1,
                    stepIndex: index,
                    message: "Step ID '\(step.id)' must be non-empty, start with a lowercase letter or underscore, and contain only lowercase letters, digits, and underscores.",
                    suggestion: "Use a simple snake_case identifier like 'fetch_data' or 'sort_posts'."
                )
            }

            // Check for duplicate step IDs
            let preceding = spec.pipeline.prefix(index)
            if preceding.contains(where: { $0.id == step.id }) {
                throw SpecValidationError(
                    pass: 1,
                    stepIndex: index,
                    message: "Duplicate step ID '\(step.id)'.",
                    suggestion: "Each step must have a unique ID."
                )
            }

            // Check required parameters
            if let required = requiredParams[step.skill] {
                for param in required {
                    let value = step.params[param]
                    if value == nil || value?.isNull == true {
                        throw SpecValidationError(
                            pass: 1,
                            stepIndex: index,
                            message: "Step '\(step.id)' (skill '\(step.skill.rawValue)') is missing required parameter '\(param)'.",
                            suggestion: "Add the '\(param)' parameter. Check the skill's parameter schema for details."
                        )
                    }
                }
            }
        }
    }

    // MARK: - Pass 2: Reference Validation

    /// Validates that all `{{step_id.output}}` references point to preceding steps.
    private static func pass2References(_ spec: WidgetPipelineSpec) throws {
        var availableSteps = Set<String>()

        for (index, step) in spec.pipeline.enumerated() {
            let refs = extractReferences(from: step.params)
            for ref in refs {
                if !availableSteps.contains(ref) {
                    throw SpecValidationError(
                        pass: 2,
                        stepIndex: index,
                        message: "Step '\(step.id)' references '{{\\(ref).output}}' but step '\(ref)' does not exist or comes after this step.",
                        suggestion: "Ensure referenced steps appear before this step in the pipeline."
                    )
                }
            }
            availableSteps.insert(step.id)
        }
    }

    // MARK: - Pass 3: Last Step Is Render

    /// Validates that the final step is a render skill and render skills only appear in terminal position.
    private static func pass3LastStepIsRender(_ spec: WidgetPipelineSpec) throws {
        guard let lastStep = spec.pipeline.last else {
            throw SpecValidationError(
                pass: 3,
                stepIndex: nil,
                message: "Pipeline is empty.",
                suggestion: "Add at least one step ending with a render skill."
            )
        }

        if !lastStep.skill.isRenderSkill {
            throw SpecValidationError(
                pass: 3,
                stepIndex: spec.pipeline.count - 1,
                message: "Last step '\(lastStep.id)' uses skill '\(lastStep.skill.rawValue)' which is not a render skill.",
                suggestion: "The final step must use one of: render_list, render_stat_card, render_chart, render_table, render_composite."
            )
        }

        // Ensure render skills only appear in the last position
        for (index, step) in spec.pipeline.dropLast().enumerated() {
            if step.skill.isRenderSkill {
                throw SpecValidationError(
                    pass: 3,
                    stepIndex: index,
                    message: "Render skill '\(step.skill.rawValue)' at step \(index) is not allowed in non-terminal position.",
                    suggestion: "Render skills must only appear as the final pipeline step. Move data transformations before the render step."
                )
            }
        }
    }

    // MARK: - Pass 4: URL Allowlist

    /// Validates that `fetch_rest_api` URLs match curated domains.
    private static func pass4URLAllowlist(_ spec: WidgetPipelineSpec) throws {
        for (index, step) in spec.pipeline.enumerated() {
            guard step.skill == .fetchRestApi else { continue }

            guard let urlValue = step.params["url"]?.stringValue, !urlValue.isEmpty else {
                throw SpecValidationError(
                    pass: 4,
                    stepIndex: index,
                    message: "fetch_rest_api step '\(step.id)' is missing a 'url' parameter.",
                    suggestion: "Provide an HTTPS URL from an allowed domain."
                )
            }

            // Skip template references (will be resolved at runtime)
            if urlValue.contains("{{") { continue }

            guard let url = URL(string: urlValue), url.scheme == "https" else {
                throw SpecValidationError(
                    pass: 4,
                    stepIndex: index,
                    message: "URL '\(urlValue)' must use HTTPS.",
                    suggestion: "Use an HTTPS URL."
                )
            }

            guard let host = url.host, FetchRestApiSkill.allowedDomains.contains(host) else {
                throw SpecValidationError(
                    pass: 4,
                    stepIndex: index,
                    message: "Domain '\(url.host ?? "")' is not in the allowed domain list.",
                    suggestion: "Use one of the allowed domains: \(FetchRestApiSkill.allowedDomains.sorted().joined(separator: ", "))."
                )
            }
        }
    }

    // MARK: - Pass 5: Resource Limits

    /// Validates pipeline size and refresh interval.
    private static func pass5ResourceLimits(_ spec: WidgetPipelineSpec) throws {
        // 1-5 steps
        if spec.pipeline.isEmpty {
            throw SpecValidationError(
                pass: 5,
                stepIndex: nil,
                message: "Pipeline must have at least 1 step.",
                suggestion: nil
            )
        }
        if spec.pipeline.count > 5 {
            throw SpecValidationError(
                pass: 5,
                stepIndex: nil,
                message: "Pipeline has \(spec.pipeline.count) steps, maximum is 5.",
                suggestion: "Reduce the number of steps. Consider combining transform steps."
            )
        }

        // Max 3 fetch skills
        let fetchCount = spec.pipeline.filter { $0.skill.isFetchSkill }.count
        if fetchCount > 3 {
            throw SpecValidationError(
                pass: 5,
                stepIndex: nil,
                message: "Pipeline has \(fetchCount) fetch steps, maximum is 3.",
                suggestion: "Reduce the number of data fetching steps."
            )
        }

        // Refresh interval >= 300s
        if spec.refreshIntervalSeconds < 300 {
            throw SpecValidationError(
                pass: 5,
                stepIndex: nil,
                message: "Refresh interval is \(spec.refreshIntervalSeconds)s, minimum is 300s (5 minutes).",
                suggestion: "Set refresh_interval_seconds to at least 300."
            )
        }
    }

    // MARK: - Helpers

    /// Extract all `{{step_id.output}}` reference step IDs from a params dict.
    private static func extractReferences(from params: [String: AnyCodable]) -> Set<String> {
        var refs = Set<String>()
        let pattern = try! NSRegularExpression(pattern: #"\{\{(\w+)\.output\}\}"#)

        func scan(_ value: Any) {
            if let string = value as? String {
                let range = NSRange(string.startIndex..., in: string)
                let matches = pattern.matches(in: string, range: range)
                for match in matches {
                    if let captureRange = Range(match.range(at: 1), in: string) {
                        refs.insert(String(string[captureRange]))
                    }
                }
            } else if let array = value as? [Any] {
                array.forEach { scan($0) }
            } else if let dict = value as? [String: Any] {
                dict.values.forEach { scan($0) }
            }
        }

        for (_, codable) in params {
            scan(codable.value)
        }
        return refs
    }
}
