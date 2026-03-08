import Foundation

struct AgentRuntimeStatus: Equatable, Sendable {
    let iteration: Int
    let maxSteps: Int
    let recentErrorCount: Int
    let guardrailWarning: String?
    let pageProgress: String?
}

/// Builds prompts for the agent's LLM interactions.
enum AgentPromptBuilder {
    /// Static instructions that live on the logical thread.
    static let threadInstructions = """
    You are a browser automation agent. Analyze the reduced page observation and choose the next action.

    Return structured data matching the provided schema.
    Put brief reasoning in the `thought` field.
    Put exactly one action in the `action` field and set only the parameters relevant to that action.

    AVAILABLE ACTIONS:
    click                - Click element by ID
    type                 - Type text into an element
    press_enter          - Press enter key
    scroll               - Scroll the page
    navigate             - Go to URL
    back                 - Go back to the previous page
    read_text            - Read the text content near an element
    extract_content      - Get the full text content of the current page
    read_links           - List links on the current page (compatibility fallback)
    collect_links        - Deterministically collect matching links from the current page into the result set
    advance_pagination   - Navigate to the next pagination target for the crawl
    new_tab              - Open a new blank tab (agent stays on current tab)
    open_tab             - Open a URL in a new tab (agent stays on current tab)
    switch_tab           - Switch to tab by 1-based index (rebinds agent to that tab)
    wait_for_user        - Ask the user to intervene
    wait                 - Pause briefly before trying again
    done                 - Call this as soon as the task objective is satisfied

    RULES:
    - For paginated collection tasks, the executor automatically collects matching links once per newly observed crawl page.
    - Prefer `collect_links` over `read_links` when the task is to build a list of links.
    - Prefer `advance_pagination` over raw clicks for collection tasks when a next page is available.
    - Do not call `done` for paginated collection tasks until the requested page budget is reached or pagination is exhausted.
    - Use `done` immediately once the result set is complete enough for the task.
    - If a captcha or challenge is present, use `wait_for_user`.
    - If repeated actions are failing, choose a different action instead of retrying the same thing.
    - Return only structured data matching the schema.
    """

    static func buildPrompt(
        task: String,
        intent: AgentTaskIntent,
        observation: ReducedPageObservation,
        runtimeStatus: AgentRuntimeStatus,
        accumulatorSummary: String?
    ) -> String {
        var lines: [String] = []
        lines.append("TASK: \(task)")
        lines.append("")
        lines.append("RUNTIME STATUS:")
        lines.append("Step \(runtimeStatus.iteration)/\(runtimeStatus.maxSteps)")

        if let pageLimit = intent.pageLimit {
            lines.append("Requested page limit: \(pageLimit)")
        }
        if !intent.sourceHosts.isEmpty {
            lines.append("Source hosts: \(intent.sourceHosts.joined(separator: ", "))")
        }
        if !intent.targetHosts.isEmpty {
            lines.append("Target hosts: \(intent.targetHosts.joined(separator: ", "))")
        }
        if runtimeStatus.recentErrorCount > 0 {
            lines.append("Recent errors: \(runtimeStatus.recentErrorCount)")
        }
        if let pageProgress = runtimeStatus.pageProgress, !pageProgress.isEmpty {
            lines.append("Progress note: \(pageProgress)")
        }
        if let warning = runtimeStatus.guardrailWarning {
            lines.append("Warning: \(warning)")
        }

        if let accumulatorSummary, !accumulatorSummary.isEmpty {
            lines.append("")
            lines.append(accumulatorSummary)
        }

        lines.append("")
        lines.append("CURRENT PAGE:")
        lines.append(observation.textRepresentation)
        lines.append("")

        if intent.isLinkCollection {
            lines.append("TASK HINT:")
            lines.append("This is a link-collection task. Collection happens automatically once per newly observed crawl page. Prefer pagination/navigation actions over reading large raw content, and use `collect_links` only if you need to retry collection on the current page.")
            lines.append("")
        }

        lines.append("What should I do next?")
        return lines.joined(separator: "\n")
    }
}
