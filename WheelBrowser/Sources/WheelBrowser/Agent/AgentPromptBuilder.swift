import Foundation

/// Builds prompts for the agent's LLM interactions.
enum AgentPromptBuilder {

    /// The base system prompt that instructs the LLM on response format and available actions.
    static let systemPrompt = """
    You are a browser automation agent. Analyze the page snapshot and decide what action to take.

    RESPONSE FORMAT (you must follow this exactly):
    THOUGHT: [your reasoning]
    ACTION: [one action]

    AVAILABLE ACTIONS:
    click(id)              - Click element by ID
    click(id, modifiers)   - Click with modifier keys (shift, command, control, option). Combine with +, e.g. click(5, shift+command)
    type(id, "text")       - Type text into element
    press_enter        - Press enter key
    scroll(up/down)    - Scroll the page
    navigate("url")    - Go to URL
    back()             - Go back to the previous page (use when stuck or need to try a different path)
    read_text(id)      - Read the text content near an element (use for extracting information)
    extract_content    - Get the full text content of the current page
    read_links         - List all links on the current page (capped at 50)
    new_tab            - Open a new blank tab (agent stays on current tab)
    open_tab("url")    - Open a URL in a new tab (agent stays on current tab)
    switch_tab(index)  - Switch to tab by 1-based index (rebinds agent to that tab)
    done("summary")    - IMPORTANT: Call this when the task is complete!

    WHEN TO CALL done():
    - The requested information is visible on the page
    - The requested action has been performed
    - You have navigated to the target page
    - The search results are showing
    - There is nothing more to do

    WHEN TO CALL back():
    - You're stuck on a page that doesn't help with the task
    - The current approach isn't working and you want to try a different path
    - You accidentally navigated to the wrong page

    CAPTCHA/CHALLENGE PAGES:
    - If you see a captcha, challenge, or "verify you are human" page, call wait_for_user("reason")
    - The user will solve the captcha and the page will update automatically

    CORRECT EXAMPLES:
    THOUGHT: I need to click the search button.
    ACTION: click(5)

    THOUGHT: The search results are now showing. Task complete.
    ACTION: done("Successfully searched and found results")

    THOUGHT: This page isn't what I need, let me go back and try a different link.
    ACTION: back()

    THOUGHT: I need to read the article text near the heading to extract the answer.
    ACTION: read_text(12)

    THOUGHT: I need the full page text to analyze the content.
    ACTION: extract_content

    RULES:
    - Call done() as soon as the task objective is achieved
    - Do NOT keep taking actions after the task is complete
    - If stuck in a loop, try back() to take a different approach
    - Output ONLY plain text with THOUGHT: and ACTION: labels
    - Do NOT use JSON, XML, special tokens, or <|tags|>
    """

    /// Build a dynamic system prompt with contextual additions based on current state
    static func buildSystemPrompt(stepsRemaining: Int, maxSteps: Int, recentErrors: Int) -> String {
        var prompt = systemPrompt

        // Steps remaining warning
        if stepsRemaining <= 10 && stepsRemaining > 0 {
            prompt += "\n\nIMPORTANT: You have only \(stepsRemaining) steps remaining out of \(maxSteps). "
            prompt += "Prioritize completing the task quickly. If the objective is mostly achieved, call done()."
        }

        // Error recovery guidance
        if recentErrors >= 2 {
            prompt += "\n\nNOTE: Several recent actions have failed. Consider:"
            prompt += "\n- Taking a fresh snapshot by trying a different action"
            prompt += "\n- The page may have changed since your last observation"
            prompt += "\n- Element IDs may have shifted; look at the current page state carefully"
            prompt += "\n- If an element keeps failing, try a different approach to achieve the same goal"
        }

        return prompt
    }

    /// Build the user prompt for the LLM, incorporating task, page state, and history.
    static func buildPrompt(task: String, snapshot: PageSnapshot, previousSteps: [AgentStep]) -> String {
        var prompt = "TASK: \(task)\n\n"
        prompt += "CURRENT PAGE STATE:\n"
        prompt += snapshot.textRepresentation
        prompt += "\n\n"

        // Two-tier history: compressed older steps + full detail of recent steps
        // Adaptive window: base 4 steps, +1 per recent error, up to 8
        let recentErrorCount = previousSteps.suffix(10).filter { $0.type == .error }.count
        let recentWindowSize = min(4 + recentErrorCount, 8)
        if previousSteps.count > recentWindowSize {
            let olderSteps = Array(previousSteps.prefix(previousSteps.count - recentWindowSize))
            let compressed = compressSteps(olderSteps)
            if !compressed.isEmpty {
                prompt += "EARLIER HISTORY (summary):\n"
                prompt += compressed
                prompt += "\n\n"
            }
        }

        // Tier 2: Full detail of recent steps (always include errors regardless of window)
        let recentSteps = previousSteps.suffix(recentWindowSize)
        if !recentSteps.isEmpty {
            prompt += "RECENT HISTORY:\n"
            for step in recentSteps {
                let typeLabel: String
                switch step.type {
                case .observation: typeLabel = "OBSERVED"
                case .thought: typeLabel = "THOUGHT"
                case .action: typeLabel = "ACTION"
                case .result: typeLabel = "RESULT"
                case .error: typeLabel = "ERROR"
                case .done: typeLabel = "DONE"
                }
                prompt += "\(typeLabel): \(step.content)\n"
            }
            prompt += "\n"
        }

        // Check for repeated actions (loop detection hint for LLM)
        let recentActions = previousSteps.filter { $0.type == .action }.suffix(3).map { $0.content }
        let isLooping = recentActions.count >= 2 && Set(recentActions).count == 1

        let stepCount = previousSteps.filter { $0.type == .action }.count

        if isLooping {
            prompt += "WARNING: You have repeated the same action multiple times. Consider if the task is already complete and call done(\"summary\") if so.\n\n"
        } else if stepCount >= 5 {
            prompt += "REMINDER: If the task objective has been achieved, call done(\"summary\") to complete.\n\n"
        }

        prompt += "What should I do next? If the task is complete, call done(\"summary\").\n"
        return prompt
    }

    // MARK: - Step Compression

    /// Compress older steps into a summary grouped by page visited
    private static func compressSteps(_ steps: [AgentStep]) -> String {
        guard !steps.isEmpty else { return "" }

        // Group steps by the pages they were on (using observation steps as markers)
        var pages: [(url: String, actions: [String], errors: [String])] = []
        var currentURL = ""
        var currentActions: [String] = []
        var currentErrors: [String] = []

        for step in steps {
            switch step.type {
            case .observation:
                // Start a new page group if URL changed
                if let urlLine = step.content.components(separatedBy: "\n")
                    .first(where: { $0.hasPrefix("URL:") }) {
                    let url = urlLine.replacingOccurrences(of: "URL: ", with: "").trimmingCharacters(in: .whitespaces)
                    if url != currentURL {
                        if !currentURL.isEmpty {
                            pages.append((url: currentURL, actions: currentActions, errors: currentErrors))
                        }
                        currentURL = url
                        currentActions = []
                        currentErrors = []
                    }
                }
            case .action:
                currentActions.append(step.content)
            case .error:
                currentErrors.append(step.content)
            default:
                break
            }
        }

        // Don't forget the last page group
        if !currentURL.isEmpty {
            pages.append((url: currentURL, actions: currentActions, errors: currentErrors))
        }

        // Build compressed summary
        var summary = ""
        for page in pages {
            let host = URL(string: page.url)?.host ?? page.url
            summary += "On \(host): "
            if page.actions.isEmpty {
                summary += "observed page"
            } else {
                summary += page.actions.joined(separator: ", ")
            }
            if !page.errors.isEmpty {
                summary += " [ERRORS: \(page.errors.joined(separator: "; "))]"
            }
            summary += "\n"
        }

        return summary
    }
}
