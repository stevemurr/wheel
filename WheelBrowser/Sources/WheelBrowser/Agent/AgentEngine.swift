import Foundation
import SwiftUI

/// Represents a single step in the agent's execution
struct AgentStep: Identifiable {
    let id = UUID()
    let type: StepType
    let content: String
    let timestamp: Date

    enum StepType {
        case observation  // Page state observed
        case thought      // LLM reasoning
        case action       // Action taken
        case result       // Action result
        case error        // Error occurred
        case done         // Task completed
    }
}

/// The result of an agent task
struct AgentResult {
    let success: Bool
    let summary: String
    let steps: [AgentStep]
}

/// Available actions the agent can take
enum AgentAction: Equatable {
    case click(elementId: Int)
    case type(elementId: Int, text: String)
    case pressEnter
    case scroll(direction: ScrollDirection)
    case navigate(url: String)
    case wait(seconds: Double)
    case done(summary: String)

    enum ScrollDirection: String {
        case up, down, top, bottom
    }
}

/// The ReAct agent engine for browser automation
@MainActor
class AgentEngine: ObservableObject {
    // MARK: - Published State

    @Published var isRunning: Bool = false
    @Published var currentTask: String = ""
    @Published var steps: [AgentStep] = []
    @Published var progress: String = ""
    @Published var error: String?

    // MARK: - Dependencies

    private let browserState: BrowserState
    private let settings: AppSettings
    private var currentTaskHandle: Task<AgentResult, Never>?

    // MARK: - Configuration

    private let maxIterations = 20
    private let systemPrompt = """
    You are a browser automation agent. You can interact with web pages to accomplish tasks.

    You will receive a snapshot of the current page showing interactive elements with IDs.
    Analyze the page and decide what action to take next.

    Available actions:
    - click(id) - Click an element by its ID number
    - type(id, "text") - Type text into an element
    - press_enter - Press enter on the focused element
    - scroll(direction) - Scroll the page (up, down, top, bottom)
    - navigate("url") - Navigate to a URL
    - wait(seconds) - Wait for a specified number of seconds
    - done("summary") - Complete the task with a summary

    Respond with EXACTLY this format:
    THOUGHT: [Your reasoning about what to do next]
    ACTION: [One action from the list above]

    Examples:
    THOUGHT: I need to click the search button to submit the query.
    ACTION: click(5)

    THOUGHT: I should type the search term into the search box.
    ACTION: type(3, "Swift programming")

    THOUGHT: The task is complete, I found the information.
    ACTION: done("Successfully searched for and found Swift programming tutorials")

    Important:
    - Always provide a THOUGHT before an ACTION
    - Only use one ACTION per response
    - Use element IDs from the snapshot
    - If you can't find the right element, try scrolling or navigating
    """

    // MARK: - Initialization

    init(browserState: BrowserState, settings: AppSettings) {
        self.browserState = browserState
        self.settings = settings
    }

    // MARK: - Public API

    /// Run an agent task
    func run(task: String) async -> AgentResult {
        guard !isRunning else {
            return AgentResult(success: false, summary: "Agent is already running", steps: [])
        }

        // Reset state
        isRunning = true
        currentTask = task
        steps = []
        error = nil
        progress = "Starting..."

        let taskHandle = Task { () -> AgentResult in
            do {
                let result = try await executeTask(task)
                return result
            } catch {
                let errorStep = AgentStep(type: .error, content: error.localizedDescription, timestamp: Date())
                await MainActor.run {
                    self.steps.append(errorStep)
                    self.error = error.localizedDescription
                }
                return AgentResult(success: false, summary: error.localizedDescription, steps: self.steps)
            }
        }

        currentTaskHandle = taskHandle

        let result = await taskHandle.value
        isRunning = false
        return result
    }

    /// Cancel the current task
    func cancel() {
        currentTaskHandle?.cancel()
        currentTaskHandle = nil
        isRunning = false
        progress = "Cancelled"
    }

    // MARK: - Private Methods

    private func executeTask(_ task: String) async throws -> AgentResult {
        var iteration = 0

        while iteration < maxIterations {
            try Task.checkCancellation()

            iteration += 1
            progress = "Step \(iteration)/\(maxIterations)"

            // 1. Observe - Get page snapshot
            guard let bridge = browserState.accessibilityBridge else {
                throw AgentError.webViewUnavailable
            }

            let snapshot = try await bridge.snapshot()
            let observationStep = AgentStep(
                type: .observation,
                content: "Page: \(snapshot.title)\nURL: \(snapshot.url)\n\(snapshot.elements.count) interactive elements",
                timestamp: Date()
            )
            steps.append(observationStep)

            // 2. Think - Ask LLM for next action
            let prompt = buildPrompt(task: task, snapshot: snapshot, previousSteps: steps)
            let llmResponse = try await callLLM(prompt: prompt)

            // Parse thought and action
            guard let (thought, action) = parseResponse(llmResponse) else {
                let errorStep = AgentStep(type: .error, content: "Failed to parse LLM response", timestamp: Date())
                steps.append(errorStep)
                continue
            }

            let thoughtStep = AgentStep(type: .thought, content: thought, timestamp: Date())
            steps.append(thoughtStep)

            let actionStep = AgentStep(type: .action, content: describeAction(action), timestamp: Date())
            steps.append(actionStep)

            // 3. Act - Execute the action
            do {
                let result = try await executeAction(action, bridge: bridge)

                if case .done(let summary) = action {
                    let doneStep = AgentStep(type: .done, content: summary, timestamp: Date())
                    steps.append(doneStep)
                    return AgentResult(success: true, summary: summary, steps: steps)
                }

                let resultStep = AgentStep(type: .result, content: result, timestamp: Date())
                steps.append(resultStep)

                // Small delay between actions
                try await Task.sleep(nanoseconds: 500_000_000)

            } catch {
                let errorStep = AgentStep(type: .error, content: error.localizedDescription, timestamp: Date())
                steps.append(errorStep)
            }
        }

        throw AgentError.maxIterationsReached
    }

    private func buildPrompt(task: String, snapshot: PageSnapshot, previousSteps: [AgentStep]) -> String {
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

        prompt += "What should I do next to complete the task?\n"
        return prompt
    }

    private func parseResponse(_ response: String) -> (thought: String, action: AgentAction)? {
        // Extract THOUGHT
        guard let thoughtMatch = response.range(of: "THOUGHT:", options: .caseInsensitive),
              let actionMatch = response.range(of: "ACTION:", options: .caseInsensitive) else {
            return nil
        }

        let thoughtStart = thoughtMatch.upperBound
        let thoughtEnd = actionMatch.lowerBound
        let thought = String(response[thoughtStart..<thoughtEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract ACTION
        let actionString = String(response[actionMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse action
        guard let action = parseAction(actionString) else {
            return nil
        }

        return (thought, action)
    }

    private func parseAction(_ actionString: String) -> AgentAction? {
        let trimmed = actionString.trimmingCharacters(in: .whitespacesAndNewlines)

        // click(id)
        if let match = trimmed.range(of: #"click\s*\(\s*(\d+)\s*\)"#, options: .regularExpression) {
            let idStr = trimmed[match].replacingOccurrences(of: "click", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let id = Int(idStr) {
                return .click(elementId: id)
            }
        }

        // type(id, "text")
        if let match = trimmed.range(of: #"type\s*\(\s*(\d+)\s*,\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let content = String(trimmed[match])
            // Extract ID and text
            if let idRange = content.range(of: #"\d+"#, options: .regularExpression),
               let textRange = content.range(of: #"[\"'](.+?)[\"']"#, options: .regularExpression) {
                let id = Int(content[idRange]) ?? 0
                var text = String(content[textRange])
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return .type(elementId: id, text: text)
            }
        }

        // press_enter
        if trimmed.lowercased().hasPrefix("press_enter") {
            return .pressEnter
        }

        // scroll(direction)
        if let match = trimmed.range(of: #"scroll\s*\(\s*(\w+)\s*\)"#, options: .regularExpression) {
            let dirStr = String(trimmed[match])
                .replacingOccurrences(of: "scroll", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if let direction = AgentAction.ScrollDirection(rawValue: dirStr) {
                return .scroll(direction: direction)
            }
        }

        // navigate("url")
        if let match = trimmed.range(of: #"navigate\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let url = String(trimmed[match])
                .replacingOccurrences(of: "navigate", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return .navigate(url: url)
        }

        // wait(seconds)
        if let match = trimmed.range(of: #"wait\s*\(\s*([\d.]+)\s*\)"#, options: .regularExpression) {
            let secStr = String(trimmed[match])
                .replacingOccurrences(of: "wait", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let seconds = Double(secStr) {
                return .wait(seconds: seconds)
            }
        }

        // done("summary")
        if let match = trimmed.range(of: #"done\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let summary = String(trimmed[match])
                .replacingOccurrences(of: "done", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return .done(summary: summary)
        }

        return nil
    }

    private func describeAction(_ action: AgentAction) -> String {
        switch action {
        case .click(let id):
            return "Click element #\(id)"
        case .type(let id, let text):
            return "Type \"\(text)\" into element #\(id)"
        case .pressEnter:
            return "Press Enter"
        case .scroll(let direction):
            return "Scroll \(direction.rawValue)"
        case .navigate(let url):
            return "Navigate to \(url)"
        case .wait(let seconds):
            return "Wait \(seconds) seconds"
        case .done(let summary):
            return "Done: \(summary)"
        }
    }

    private func executeAction(_ action: AgentAction, bridge: AccessibilityBridge) async throws -> String {
        switch action {
        case .click(let elementId):
            try await bridge.click(elementId: elementId)
            try await bridge.waitForLoad(timeout: 3.0)
            return "Clicked element #\(elementId)"

        case .type(let elementId, let text):
            try await bridge.type(elementId: elementId, text: text)
            return "Typed \"\(text)\" into element #\(elementId)"

        case .pressEnter:
            try await bridge.pressEnter()
            try await bridge.waitForLoad(timeout: 3.0)
            return "Pressed Enter"

        case .scroll(let direction):
            switch direction {
            case .up:
                try await bridge.scroll(deltaY: -300)
            case .down:
                try await bridge.scroll(deltaY: 300)
            case .top:
                try await bridge.scrollToTop()
            case .bottom:
                try await bridge.scrollToBottom()
            }
            return "Scrolled \(direction.rawValue)"

        case .navigate(let urlString):
            var url = urlString
            if !url.contains("://") {
                url = "https://\(url)"
            }
            if let parsedURL = URL(string: url) {
                browserState.navigate(to: parsedURL)
                try await bridge.waitForLoad(timeout: 10.0)
                return "Navigated to \(url)"
            } else {
                throw AgentError.navigationFailed("Invalid URL: \(urlString)")
            }

        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return "Waited \(seconds) seconds"

        case .done(let summary):
            return summary
        }
    }

    // MARK: - LLM Integration

    private func callLLM(prompt: String) async throws -> String {
        guard let baseURL = settings.llmBaseURL else {
            throw AgentError.llmNotConfigured
        }

        let endpoint = baseURL.appendingPathComponent("chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add API key if configured
        if settings.useAPIKey && settings.hasAPIKey {
            request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": settings.selectedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentError.llmRequestFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentError.llmRequestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AgentError.invalidLLMResponse("Could not parse response")
        }

        return content
    }
}
