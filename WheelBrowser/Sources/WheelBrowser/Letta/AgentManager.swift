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
    private let conversationManager = ConversationManager.shared

    /// Uses the unified system prompt, respecting user customization
    private var systemPrompt: String {
        SystemPromptConfig.chatPrompt
    }

    /// Pending retry info for failed messages
    private var lastFailedContent: String?
    private var lastFailedPageContexts: [PageContext] = []

    private init() {
        // Resume the most recent conversation if available
        loadLastConversation()
    }

    private func loadLastConversation() {
        if let recent = conversationManager.savedConversations.first {
            conversationManager.resumeConversation(recent)
            messages = conversationManager.messages
            // Rebuild conversation history for API calls
            conversationHistory = messages
                .filter { $0.role == .user || $0.role == .assistant }
                .map { ["role": $0.role.rawValue, "content": $0.content] }
        }
    }

    /// Safely update a message at the given index, no-op if out of bounds
    private func safeUpdateMessage(at index: Int, update: (inout ChatMessage) -> Void) {
        guard messages.indices.contains(index) else { return }
        update(&messages[index])
    }

    /// Send a message with multiple page contexts
    func sendMessage(_ content: String, pageContexts: [PageContext]) async {
        isLoading = true
        lastFailedPageContexts = pageContexts

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

    /// Retry the last failed message
    func retryLastFailedMessage() async {
        guard let content = lastFailedContent else { return }

        // Remove the failed assistant message from the end
        if let lastMsg = messages.last, lastMsg.isFailed {
            messages.removeLast()
        }

        let contexts = lastFailedPageContexts
        lastFailedContent = nil
        lastFailedPageContexts = []

        await sendMessage(content, pageContexts: contexts)
    }

    private func sendMessageInternal(content: String, fullMessage: String) async {
        isLoading = true

        // Store for potential retry
        lastFailedContent = content

        // Add user message to chat UI
        let userMessage = ChatMessage(
            role: .user,
            content: content,
            timestamp: Date(),
            modelUsed: settings.selectedModel,
            conversationId: conversationManager.currentConversation?.id
        )
        messages.append(userMessage)
        conversationManager.addMessage(userMessage)

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
            let maxUpdateInterval: TimeInterval = WindowConstants.streamingFlushInterval

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
                            safeUpdateMessage(at: idx) { $0.content = thinkingBuffer }
                        }
                        lastUpdateTime = now
                    }

                case .content(let contentText):
                    pendingChunk += contentText

                    // Flush on complete markdown structures or timeout
                    if shouldFlushBuffer(pendingChunk) || timeSinceUpdate >= maxUpdateInterval {
                        buffer += pendingChunk
                        pendingChunk = ""
                        safeUpdateMessage(at: assistantIndex) { $0.content = buffer }
                        lastUpdateTime = now
                    }
                }
            }

            // Flush any remaining thinking content
            if !pendingThinkingChunk.isEmpty {
                thinkingBuffer += pendingThinkingChunk
                if let idx = thinkingIndex {
                    safeUpdateMessage(at: idx) { msg in
                        msg.content = thinkingBuffer
                        msg.isStreaming = false
                    }
                }
            } else if let idx = thinkingIndex {
                safeUpdateMessage(at: idx) { $0.isStreaming = false }
            }

            // Flush any remaining content
            if !pendingChunk.isEmpty {
                buffer += pendingChunk
            }

            // Final update with complete content
            safeUpdateMessage(at: assistantIndex) { msg in
                msg.content = buffer
                msg.isStreaming = false
                msg.modelUsed = self.settings.selectedModel
            }

            // Add final response to conversation history
            conversationHistory.append(["role": "assistant", "content": buffer])

            // Persist the assistant message
            let assistantMessage = messages[assistantIndex]
            conversationManager.addMessage(assistantMessage)

            // Clear retry state on success
            lastFailedContent = nil
            lastFailedPageContexts = []
        } catch {
            // Mark thinking as done if we had any
            if let idx = thinkingIndex {
                safeUpdateMessage(at: idx) { $0.isStreaming = false }
            }
            safeUpdateMessage(at: assistantIndex) { msg in
                msg.content = "Error: \(error.localizedDescription)"
                msg.isStreaming = false
                msg.isFailed = true
            }
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
        conversationManager.saveCurrentConversation()
        conversationManager.clearCurrentConversation()
        messages.removeAll()
        conversationHistory.removeAll()
        lastFailedContent = nil
        lastFailedPageContexts = []
    }

    func resetAgent() async {
        clearMessages()
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
