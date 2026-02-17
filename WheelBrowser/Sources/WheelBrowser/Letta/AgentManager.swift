import Foundation
import Combine

@MainActor
class AgentManager: ObservableObject {
    static let shared = AgentManager()

    @Published var isReady = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var messages: [ChatMessage] = []

    private var settings = AppSettings.shared
    private var conversationHistory: [[String: String]] = []

    private let systemPrompt = """
    You are a helpful AI assistant integrated into a web browser called Wheel.

    Your role is to help users:
    - Understand and summarize web page content
    - Answer questions about pages they're viewing
    - Help with research and information gathering

    When the user asks about the current page, use the page context provided in the message.
    Be concise but helpful. Focus on the most relevant information for the user's question.
    """

    private init() {}

    func initialize() async {
        isReady = true
    }

    func sendMessage(_ content: String, pageContext: PageContext? = nil) async {
        isLoading = true

        // Build message with context
        var fullMessage = content
        if let context = pageContext {
            fullMessage = """
            [Current Page Context]
            URL: \(context.url)
            Title: \(context.title)
            Content Preview:
            \(context.textContent.prefix(4000))

            [User Question]
            \(content)
            """
        }

        // Add user message to chat UI
        let userMessage = ChatMessage(role: .user, content: content, timestamp: Date())
        messages.append(userMessage)

        // Add to conversation history
        conversationHistory.append(["role": "user", "content": fullMessage])

        // Add placeholder for assistant response
        let assistantMessage = ChatMessage(role: .assistant, content: "", timestamp: Date())
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        do {
            let responseText = try await callLLM()

            // Add to conversation history
            conversationHistory.append(["role": "assistant", "content": responseText])

            messages[assistantIndex] = ChatMessage(
                role: .assistant,
                content: responseText,
                timestamp: Date()
            )
        } catch {
            messages[assistantIndex] = ChatMessage(
                role: .assistant,
                content: "Error: \(error.localizedDescription)",
                timestamp: Date()
            )
        }

        isLoading = false
    }

    private func callLLM() async throws -> String {
        guard let url = URL(string: "\(settings.llmEndpoint)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Build messages array with system prompt
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: conversationHistory)

        let body: [String: Any] = [
            "model": settings.selectedModel,
            "messages": apiMessages,
            "max_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }

        return content
    }

    func storePageVisit(_ context: PageContext) async {
        // Store in conversation context for future reference
        let entry = "Previously visited: \(context.title) (\(context.url))"
        conversationHistory.append(["role": "system", "content": entry])
    }

    func clearMessages() {
        messages.removeAll()
        conversationHistory.removeAll()
    }

    func resetAgent() async {
        messages.removeAll()
        conversationHistory.removeAll()
        isReady = true
    }
}

struct PageContext {
    let url: String
    let title: String
    let textContent: String
}

enum LLMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid LLM endpoint URL"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .parseError:
            return "Failed to parse LLM response"
        }
    }
}
