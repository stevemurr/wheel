import Foundation
import Combine

@MainActor
class AgentManager: ObservableObject {
    static let shared = AgentManager()

    @Published var isReady = true
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

        // Track thinking message index (if we receive any thinking content)
        var thinkingIndex: Int? = nil
        var thinkingBuffer = ""
        var pendingThinkingChunk = ""

        // Add placeholder for assistant response with streaming flag
        messages.append(ChatMessage(role: .assistant, content: "", timestamp: Date(), isStreaming: true))
        var assistantIndex = messages.count - 1

        do {
            var buffer = ""
            var pendingChunk = ""
            var lastUpdateTime = Date()
            let maxUpdateInterval: TimeInterval = 0.1 // Force update at least every 100ms

            for try await chunk in streamLLM() {
                let now = Date()
                let timeSinceUpdate = now.timeIntervalSince(lastUpdateTime)

                switch chunk {
                case .thinking(let thinkingContent):
                    // If this is the first thinking content, insert a thinking message before the assistant message
                    if thinkingIndex == nil {
                        // Insert thinking message right before the current assistant message
                        let thinkingMessage = ChatMessage(role: .thinking, content: "", timestamp: Date(), isStreaming: true)
                        messages.insert(thinkingMessage, at: assistantIndex)
                        thinkingIndex = assistantIndex
                        assistantIndex += 1 // Shift assistant index since we inserted before it
                    }

                    pendingThinkingChunk += thinkingContent

                    // Flush thinking content on complete sentences or timeout
                    if shouldFlushBuffer(pendingThinkingChunk) || timeSinceUpdate >= maxUpdateInterval {
                        thinkingBuffer += pendingThinkingChunk
                        pendingThinkingChunk = ""
                        if let idx = thinkingIndex {
                            messages[idx].content = thinkingBuffer
                        }
                        lastUpdateTime = now
                    }

                case .content(let contentText):
                    pendingChunk += contentText

                    // Flush on complete markdown structures or timeout
                    if shouldFlushBuffer(pendingChunk) || timeSinceUpdate >= maxUpdateInterval {
                        buffer += pendingChunk
                        pendingChunk = ""
                        messages[assistantIndex].content = buffer
                        lastUpdateTime = now
                    }
                }
            }

            // Flush any remaining thinking content
            if !pendingThinkingChunk.isEmpty {
                thinkingBuffer += pendingThinkingChunk
                if let idx = thinkingIndex {
                    messages[idx].content = thinkingBuffer
                    messages[idx].isStreaming = false
                }
            } else if let idx = thinkingIndex {
                messages[idx].isStreaming = false
            }

            // Flush any remaining content
            if !pendingChunk.isEmpty {
                buffer += pendingChunk
            }

            // Final update with complete content
            messages[assistantIndex].content = buffer
            messages[assistantIndex].isStreaming = false

            // Add final response to conversation history
            conversationHistory.append(["role": "assistant", "content": buffer])
        } catch {
            // Mark thinking as done if we had any
            if let idx = thinkingIndex {
                messages[idx].isStreaming = false
            }
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            messages[assistantIndex].isStreaming = false
        }

        isLoading = false
    }

    /// Represents a chunk from the streaming LLM response
    enum StreamChunk {
        case content(String)
        case thinking(String)
    }

    private func streamLLM() -> AsyncThrowingStream<StreamChunk, Error> {
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
                    for try await jsonString in bytes.sseEvents {
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any] else {
                            continue
                        }

                        // Check for reasoning/thinking content (Claude extended thinking, OpenAI reasoning)
                        // Different APIs use different field names for reasoning traces
                        if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                            continuation.yield(.thinking(thinking))
                        } else if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                            continuation.yield(.thinking(reasoning))
                        } else if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                            continuation.yield(.thinking(reasoning))
                        }

                        // Regular content
                        if let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.content(content))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Detects complete markdown structures that are safe flush points
    /// This reduces UI updates while ensuring meaningful visual progress
    private func shouldFlushBuffer(_ buffer: String) -> Bool {
        guard !buffer.isEmpty else { return false }

        // Paragraph break - most common flush point
        if buffer.hasSuffix("\n\n") {
            return true
        }

        // Code block boundaries
        if buffer.hasSuffix("```\n") || buffer.hasSuffix("```") {
            return true
        }

        // LaTeX block boundaries
        if buffer.hasSuffix("$$\n") || buffer.hasSuffix("$$") {
            return true
        }

        // End of sentence followed by space (natural reading break)
        if buffer.count >= 2 {
            let lastTwo = String(buffer.suffix(2))
            if lastTwo == ". " || lastTwo == "! " || lastTwo == "? " {
                return true
            }
        }

        // List item complete (newline after list content)
        if buffer.contains("\n") {
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if let lastLine = lines.last, lastLine.isEmpty {
                // Previous line was complete
                if lines.count >= 2 {
                    let prevLine = String(lines[lines.count - 2])
                    // Check if it was a list item or heading
                    let trimmed = prevLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                       trimmed.hasPrefix("# ") || trimmed.hasPrefix("> ") ||
                       trimmed.first?.isNumber == true && trimmed.contains(". ") {
                        return true
                    }
                }
            }
        }

        // Heading complete
        if buffer.hasSuffix("\n") && buffer.contains("#") {
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                let prevLine = String(lines[lines.count - 2])
                if prevLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    return true
                }
            }
        }

        // Table row complete
        if buffer.hasSuffix("|\n") {
            return true
        }

        // Fallback: flush on any newline if buffer is getting large
        if buffer.count > 200 && buffer.hasSuffix("\n") {
            return true
        }

        return false
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
