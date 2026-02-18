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

    /// Send a message with multiple page contexts
    func sendMessage(_ content: String, pageContexts: [PageContext]) async {
        isLoading = true

        // Build message with multiple contexts
        var fullMessage = content
        if !pageContexts.isEmpty {
            var contextParts: [String] = []
            for (index, context) in pageContexts.enumerated() {
                let header = pageContexts.count == 1 ? "[Page Context]" : "--- Page \(index + 1) ---"
                contextParts.append("""
                \(header)
                URL: \(context.url)
                Title: \(context.title)
                Content Preview:
                \(context.textContent.prefix(4000))
                """)
            }
            fullMessage = """
            \(contextParts.joined(separator: "\n\n"))

            [User Question]
            \(content)
            """
        }

        await sendMessageInternal(content: content, fullMessage: fullMessage)
    }

    /// Backward-compatible single context method
    func sendMessage(_ content: String, pageContext: PageContext? = nil) async {
        if let context = pageContext {
            await sendMessage(content, pageContexts: [context])
        } else {
            await sendMessage(content, pageContexts: [])
        }
    }

    private func sendMessageInternal(content: String, fullMessage: String) async {
        isLoading = true

        // Add user message to chat UI
        let userMessage = ChatMessage(role: .user, content: content, timestamp: Date())
        messages.append(userMessage)

        // Add to conversation history
        conversationHistory.append(["role": "user", "content": fullMessage])

        // Add placeholder for assistant response with streaming flag
        let messageId = UUID()
        messages.append(ChatMessage(id: messageId, role: .assistant, content: "", timestamp: Date(), isStreaming: true))
        let assistantIndex = messages.count - 1

        do {
            var buffer = ""
            var lastUpdateTime = Date()
            let updateInterval: TimeInterval = 0.033 // ~30fps

            for try await chunk in streamLLM() {
                buffer += chunk

                // Throttle UI updates
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                    messages[assistantIndex].content = buffer
                    lastUpdateTime = now
                }
            }

            // Final update with complete content
            messages[assistantIndex].content = buffer
            messages[assistantIndex].isStreaming = false

            // Add final response to conversation history
            conversationHistory.append(["role": "assistant", "content": buffer])
        } catch {
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            messages[assistantIndex].isStreaming = false
        }

        isLoading = false
    }

    private func streamLLM() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(settings.llmEndpoint)/chat/completions") else {
                        throw LLMError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 120

                    // Add API key authentication if enabled and configured
                    if settings.useAPIKey && settings.hasAPIKey {
                        request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
                    }

                    // Build messages array with system prompt
                    var apiMessages: [[String: String]] = [
                        ["role": "system", "content": systemPrompt]
                    ]
                    apiMessages.append(contentsOf: conversationHistory)

                    let body: [String: Any] = [
                        "model": settings.selectedModel,
                        "messages": apiMessages,
                        "max_tokens": 2048,
                        "stream": true
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.invalidResponse
                    }

                    if httpResponse.statusCode != 200 {
                        throw LLMError.httpError(statusCode: httpResponse.statusCode, message: "Stream request failed")
                    }

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        // SSE format: "data: {...}" or "data: [DONE]"
                        guard line.hasPrefix("data: ") else { continue }

                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" {
                            break
                        }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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
