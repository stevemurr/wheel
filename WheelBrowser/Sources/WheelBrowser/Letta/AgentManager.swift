import Foundation
import Combine

@MainActor
class AgentManager: ObservableObject {
    static let shared = AgentManager()

    @Published var isReady = true
    @Published var isLoading = false
    @Published var error: String?
    @Published var messages: [ChatMessage] = []
    @Published var isFullPageChatActive: Bool = false

    // MARK: - Dependencies

    private var settings = AppSettings.shared
    private let conversationManager = ConversationManager.shared

    // MARK: - Extracted Services

    /// Type alias so the rest of AgentManager can refer to StreamChunk without qualification
    typealias StreamChunk = StreamingResponseProcessor.StreamChunk

    private let streamProcessor = StreamingResponseProcessor()
    private let bufferFlusher = MarkdownBufferFlusher()

    // MARK: - Per-Tab Conversation State

    /// Snapshot of a conversation's state, cached when switching tabs.
    private struct ConversationSnapshot {
        var messages: [ChatMessage]
        var conversationHistory: [[String: String]]
        var lastFailedContent: String?
        var lastFailedPageContexts: [PageContext]
    }

    /// Cached conversation states keyed by tab conversationId.
    private var snapshots: [UUID: ConversationSnapshot] = [:]

    /// The conversationId of the currently active conversation.
    private(set) var activeConversationId: UUID?

    // MARK: - Internal State

    private var conversationHistory: [[String: String]] = []

    /// Uses the unified system prompt, respecting user customization
    private var systemPrompt: String {
        SystemPromptConfig.chatPrompt
    }

    /// Pending retry info for failed messages
    private var lastFailedContent: String?
    private var lastFailedPageContexts: [PageContext] = []

    private init() {
        // Tabs start fresh. Conversations are restored via switchConversation()
        // + snapshots, or via reopenLastClosedTab() which preserves conversationId.
    }

    /// Switch to a different tab's conversation.
    /// Saves the current conversation state and loads the target one.
    func switchConversation(to conversationId: UUID) {
        guard conversationId != activeConversationId else { return }

        // Save current state
        if let currentId = activeConversationId {
            snapshots[currentId] = ConversationSnapshot(
                messages: messages,
                conversationHistory: conversationHistory,
                lastFailedContent: lastFailedContent,
                lastFailedPageContexts: lastFailedPageContexts
            )
        }

        activeConversationId = conversationId

        // Load target state
        if let snapshot = snapshots[conversationId] {
            messages = snapshot.messages
            conversationHistory = snapshot.conversationHistory
            lastFailedContent = snapshot.lastFailedContent
            lastFailedPageContexts = snapshot.lastFailedPageContexts
        } else {
            // New conversation — start fresh
            messages = []
            conversationHistory = []
            lastFailedContent = nil
            lastFailedPageContexts = []
        }
    }

    /// Remove a cached conversation snapshot (e.g. when a tab is closed).
    func clearSnapshot(for conversationId: UUID) {
        snapshots.removeValue(forKey: conversationId)
    }

    /// Safely update a message by its ID, no-op if the message is not found.
    /// This is safer than index-based mutation because IDs are stable even when
    /// messages are inserted or removed during streaming.
    private func safeUpdateMessage(id: UUID, update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
    }

    // MARK: - Public API

    /// Send a message with multiple page contexts
    func sendMessage(_ content: String, pageContexts: [PageContext]) async {
        isLoading = true
        lastFailedPageContexts = pageContexts

        let fullMessage = ConversationHistoryBuilder.buildFullMessage(
            content: content,
            pageContexts: pageContexts
        )

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

    // MARK: - Streaming Orchestration

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

        // Track thinking message by ID (stable across insertions)
        var thinkingMessageId: UUID? = nil
        var thinkingBuffer = ""
        var pendingThinkingChunk = ""

        // Add placeholder for assistant response with streaming flag
        let assistantPlaceholder = ChatMessage(role: .assistant, content: "", timestamp: Date(), isStreaming: true)
        let assistantMessageId = assistantPlaceholder.id
        messages.append(assistantPlaceholder)

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
                    if thinkingMessageId == nil {
                        let thinkingMessage = ChatMessage(role: .thinking, content: "", timestamp: Date(), isStreaming: true)
                        thinkingMessageId = thinkingMessage.id
                        // Insert thinking message right before the assistant message
                        if let assistantIdx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            messages.insert(thinkingMessage, at: assistantIdx)
                        } else {
                            messages.append(thinkingMessage)
                        }
                    }

                    pendingThinkingChunk += thinkingContent

                    // Flush thinking content on complete sentences or timeout
                    if bufferFlusher.shouldFlush(pendingThinkingChunk) || timeSinceUpdate >= maxUpdateInterval {
                        thinkingBuffer += pendingThinkingChunk
                        pendingThinkingChunk = ""
                        if let id = thinkingMessageId {
                            safeUpdateMessage(id: id) { $0.content = thinkingBuffer }
                        }
                        lastUpdateTime = now
                    }

                case .content(let contentText):
                    pendingChunk += contentText

                    // Flush on complete markdown structures or timeout
                    if bufferFlusher.shouldFlush(pendingChunk) || timeSinceUpdate >= maxUpdateInterval {
                        buffer += pendingChunk
                        pendingChunk = ""
                        safeUpdateMessage(id: assistantMessageId) { $0.content = buffer }
                        lastUpdateTime = now
                    }

                case .finishReason:
                    break // Handled in streamLLM()
                }
            }

            // Flush any remaining thinking content
            if !pendingThinkingChunk.isEmpty {
                thinkingBuffer += pendingThinkingChunk
                if let id = thinkingMessageId {
                    safeUpdateMessage(id: id) { msg in
                        msg.content = thinkingBuffer
                        msg.isStreaming = false
                    }
                }
            } else if let id = thinkingMessageId {
                safeUpdateMessage(id: id) { $0.isStreaming = false }
            }

            // Flush any remaining content
            if !pendingChunk.isEmpty {
                buffer += pendingChunk
            }

            // Final update with complete content
            safeUpdateMessage(id: assistantMessageId) { msg in
                msg.content = buffer
                msg.isStreaming = false
                msg.modelUsed = self.settings.selectedModel
            }

            // Add final response to conversation history
            conversationHistory.append(["role": "assistant", "content": buffer])

            // Persist the assistant message
            if let assistantMessage = messages.first(where: { $0.id == assistantMessageId }) {
                conversationManager.addMessage(assistantMessage)
            }

            // Clear retry state on success
            lastFailedContent = nil
            lastFailedPageContexts = []
        } catch {
            // Mark thinking as done if we had any
            if let id = thinkingMessageId {
                safeUpdateMessage(id: id) { $0.isStreaming = false }
            }
            safeUpdateMessage(id: assistantMessageId) { msg in
                msg.content = "Error: \(error.localizedDescription)"
                msg.isStreaming = false
                msg.isFailed = true
            }
        }

        isLoading = false
    }

    // MARK: - LLM Streaming

    private func streamLLM() -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
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

                    let apiMessages = ConversationHistoryBuilder.buildAPIMessages(
                        systemPrompt: self.systemPrompt,
                        conversationHistory: self.conversationHistory
                    )

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

                    // Parse SSE stream and classify each event
                    let processor = self.streamProcessor
                    for try await jsonString in bytes.sseEvents {
                        try Task.checkCancellation()
                        for chunk in processor.processSSEEvent(jsonString) {
                            if case .finishReason(let reason) = chunk, reason == "length" {
                                Log.Chat.warning("streamLLM: Response truncated (finish_reason=length)")
                            }
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Conversation Management

    func clearMessages() {
        conversationManager.saveCurrentConversation()
        conversationManager.clearCurrentConversation()
        messages.removeAll()
        conversationHistory.removeAll()
        lastFailedContent = nil
        lastFailedPageContexts = []
        // Also clear the cached snapshot for this conversation
        if let id = activeConversationId {
            snapshots.removeValue(forKey: id)
        }
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
