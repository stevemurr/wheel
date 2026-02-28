import Foundation

/// Builds prompts for the agent's LLM interactions.
enum AgentPromptBuilder {

    /// The system prompt that instructs the LLM on response format and available actions.
    static let systemPrompt = """
    You are a browser automation agent. Analyze the page snapshot and decide what action to take.

    RESPONSE FORMAT (you must follow this exactly):
    THOUGHT: [your reasoning]
    ACTION: [one action]

    AVAILABLE ACTIONS:
    click(id)          - Click element by ID
    type(id, "text")   - Type text into element
    press_enter        - Press enter key
    scroll(up/down)    - Scroll the page
    navigate("url")    - Go to URL
    back()             - Go back to the previous page (use when stuck or need to try a different path)
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

    RULES:
    - Call done() as soon as the task objective is achieved
    - Do NOT keep taking actions after the task is complete
    - If stuck in a loop, try back() to take a different approach
    - Output ONLY plain text with THOUGHT: and ACTION: labels
    - Do NOT use JSON, XML, special tokens, or <|tags|>
    """

    /// Build the user prompt for the LLM, incorporating task, page state, and history.
    static func buildPrompt(task: String, snapshot: PageSnapshot, previousSteps: [AgentStep]) -> String {
        var prompt = "TASK: \(task)\n\n"
        prompt += "CURRENT PAGE STATE:\n"
        prompt += snapshot.textRepresentation
        prompt += "\n\n"

        // Include recent history
        let recentSteps = previousSteps.suffix(6)
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
            prompt += "WARNING: You have repeated the same action multiple times. Consider if the task is already complete and call done() if so.\n\n"
        } else if stepCount >= 5 {
            prompt += "REMINDER: If the task objective has been achieved, call done(\"summary\") to complete.\n\n"
        }

        prompt += "What should I do next? If the task is complete, call done().\n"
        return prompt
    }
}
