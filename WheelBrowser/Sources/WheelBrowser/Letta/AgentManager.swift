import Foundation
import Observation

@MainActor
@Observable
class AgentManager {
    static let shared = AgentManager()

    var isReady = true
    var isLoading = false
    var error: String?
    var messages: [ChatMessage] = []
    var isFullPageChatActive: Bool = false
    var isStreamingActive: Bool = false
    var selectedArtifact: ChatArtifact?

    /// Text to prefill in the chat input (e.g. from follow-up suggestions).
    /// The OmniBar observes this and moves the value into `omniState.inputText`.
    var pendingInputText: String?

    /// Lightweight counter incremented on each streaming flush.
    /// Scroll observers watch this instead of `messages.last?.content` to avoid
    /// reading into the messages array (which would make them depend on all message mutations).
    var streamingScrollToken: UInt = 0

    /// The active streaming task, cancellable for stop generation
    private var activeStreamTask: Task<Void, Never>?

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

    /// Stop the current generation
    func stopGeneration() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isStreamingActive = false

        // Mark the last streaming assistant message as stopped
        if let lastIdx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[lastIdx].isStreaming = false
            messages[lastIdx].wasStoppedByUser = true
        }
        // Also stop any streaming thinking messages
        if let thinkIdx = messages.lastIndex(where: { $0.role == .thinking && $0.isStreaming }) {
            messages[thinkIdx].isStreaming = false
        }
        isLoading = false
    }

    /// Edit a user message and resend from that point (ID-based)
    func editAndResend(messageID: UUID, newContent: String, pageContexts: [PageContext]) async {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }

        // Fork conversation at the edit point
        messages = ConversationBranchManager.editMessage(
            at: messageIndex,
            newContent: newContent,
            in: messages
        )

        // Rebuild conversation history up to the edited message
        conversationHistory = messages.filter { $0.role == .user || $0.role == .assistant }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        // Send the new message
        let fullMessage = ConversationHistoryBuilder.buildFullMessage(
            content: newContent,
            pageContexts: pageContexts
        )
        // Remove the user message we just added (sendMessageInternal will re-add it)
        if messages.last?.role == .user {
            let lastMsg = messages.removeLast()
            // Also remove from conversation history
            if !conversationHistory.isEmpty { conversationHistory.removeLast() }
            _ = lastMsg // suppress unused warning
        }
        await sendMessageInternal(content: newContent, fullMessage: fullMessage)
    }

    /// Regenerate an assistant response (ID-based, falls back to last assistant message)
    func regenerateResponse(messageID: UUID? = nil) async {
        let targetIndex: Int?
        if let id = messageID {
            targetIndex = messages.firstIndex(where: { $0.id == id })
        } else {
            targetIndex = messages.lastIndex(where: { $0.role == .assistant })
        }
        guard let idx = targetIndex else { return }

        // Find the user message that preceded this response
        let userMessageIndex = messages[..<idx].lastIndex(where: { $0.role == .user })
        guard let userIdx = userMessageIndex else { return }

        let userContent = messages[userIdx].content

        // Remove from the assistant message onward
        messages = ConversationBranchManager.regenerateResponse(at: idx, in: messages)

        // Rebuild conversation history
        conversationHistory = messages.filter { $0.role == .user || $0.role == .assistant }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let fullMessage = ConversationHistoryBuilder.buildFullMessage(
            content: userContent,
            pageContexts: lastFailedPageContexts
        )

        // Re-send using internal method (user message already in messages)
        await sendMessageInternalRegenerate(fullMessage: fullMessage)
    }

    /// Parse follow-up suggestions from model output
    private func parseFollowUpSuggestions(from content: String) -> [String] {
        guard let startRange = content.range(of: "[SUGGESTIONS]"),
              let endRange = content.range(of: "[/SUGGESTIONS]") else {
            return []
        }

        let suggestionsText = String(content[startRange.upperBound..<endRange.lowerBound])
        return suggestionsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-") ? true : true }
            .map { line in
                var cleaned = line
                if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
                // Remove numbered prefixes like "1. "
                if let dotRange = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    cleaned = String(cleaned[dotRange.upperBound...])
                }
                return cleaned.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }

    /// Strip the [SUGGESTIONS] block from displayed content
    private func stripSuggestionsBlock(from content: String) -> String {
        guard let startRange = content.range(of: "[SUGGESTIONS]") else { return content }
        // Find the end tag or trim from [SUGGESTIONS] to end
        if let endRange = content.range(of: "[/SUGGESTIONS]") {
            var result = content
            result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(content[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Streaming Orchestration

    private func sendMessageInternal(content: String, fullMessage: String) async {
        isLoading = true
        isStreamingActive = true

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

        await performStreaming(forRegenerate: false)
    }

    /// Internal streaming for regeneration (user message already in messages/history)
    private func sendMessageInternalRegenerate(fullMessage: String) async {
        isLoading = true
        isStreamingActive = true
        lastFailedContent = nil

        await performStreaming(forRegenerate: true)
    }

    /// Shared streaming logic used by both sendMessageInternal and regenerate
    private func performStreaming(forRegenerate: Bool) async {
        // Track thinking message by ID (stable across insertions)
        var thinkingMessageId: UUID? = nil
        var thinkingBuffer = ""
        var pendingThinkingChunk = ""
        var thinkingStartTime: Date? = nil

        // Add placeholder for assistant response with streaming flag
        let assistantPlaceholder = ChatMessage(role: .assistant, content: "", timestamp: Date(), isStreaming: true)
        let assistantMessageId = assistantPlaceholder.id
        messages.append(assistantPlaceholder)

        // Wrap in a task so we can cancel via stopGeneration()
        let streamTask = Task { @MainActor in
            do {
                var buffer = ""
                var pendingChunk = ""
                var lastUpdateTime = Date()
                let maxUpdateInterval: TimeInterval = WindowConstants.streamingFlushInterval

                for try await chunk in streamLLM() {
                    try Task.checkCancellation()
                    let now = Date()
                    let timeSinceUpdate = now.timeIntervalSince(lastUpdateTime)

                    switch chunk {
                    case .thinking(let thinkingContent):
                        // If this is the first thinking content, insert a thinking message before the assistant message
                        if thinkingMessageId == nil {
                            thinkingStartTime = Date()
                            let thinkingMessage = ChatMessage(
                                role: .thinking,
                                content: "",
                                timestamp: Date(),
                                isStreaming: true,
                                thinkingStartTime: thinkingStartTime
                            )
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
                            streamingScrollToken &+= 1
                            lastUpdateTime = now
                        }

                    case .content(let contentText):
                        // If we were thinking, finalize thinking duration
                        if let id = thinkingMessageId, let startTime = thinkingStartTime,
                           messages.first(where: { $0.id == id })?.isStreaming == true {
                            let duration = Date().timeIntervalSince(startTime)
                            safeUpdateMessage(id: id) { msg in
                                msg.isStreaming = false
                                msg.thinkingDurationSeconds = duration
                            }
                        }

                        pendingChunk += contentText

                        // Flush on complete markdown structures or timeout
                        if bufferFlusher.shouldFlush(pendingChunk) || timeSinceUpdate >= maxUpdateInterval {
                            buffer += pendingChunk
                            pendingChunk = ""
                            safeUpdateMessage(id: assistantMessageId) { $0.content = buffer }
                            streamingScrollToken &+= 1
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
                        let duration = thinkingStartTime.map { Date().timeIntervalSince($0) }
                        safeUpdateMessage(id: id) { msg in
                            msg.content = thinkingBuffer
                            msg.isStreaming = false
                            msg.thinkingDurationSeconds = duration
                        }
                    }
                } else if let id = thinkingMessageId {
                    let duration = thinkingStartTime.map { Date().timeIntervalSince($0) }
                    safeUpdateMessage(id: id) { msg in
                        msg.isStreaming = false
                        msg.thinkingDurationSeconds = duration
                    }
                }

                // Flush any remaining content
                if !pendingChunk.isEmpty {
                    buffer += pendingChunk
                }

                // Parse follow-up suggestions from model output
                let followUps = parseFollowUpSuggestions(from: buffer)
                let displayContent = stripSuggestionsBlock(from: buffer)

                // Extract artifacts from code blocks
                let artifacts = ArtifactExtractor.extract(from: displayContent)

                // Final update with complete content
                safeUpdateMessage(id: assistantMessageId) { msg in
                    msg.content = displayContent
                    msg.isStreaming = false
                    msg.modelUsed = self.settings.selectedModel
                    msg.suggestedFollowUps = followUps
                    msg.artifacts = artifacts
                }

                // Add final response to conversation history
                conversationHistory.append(["role": "assistant", "content": displayContent])

                // Persist the assistant message
                if let assistantMessage = messages.first(where: { $0.id == assistantMessageId }) {
                    conversationManager.addMessage(assistantMessage)
                }

                // Clear retry state on success
                lastFailedContent = nil
                lastFailedPageContexts = []
            } catch is CancellationError {
                // User stopped generation - mark message as stopped
                if let id = thinkingMessageId {
                    safeUpdateMessage(id: id) { $0.isStreaming = false }
                }
                safeUpdateMessage(id: assistantMessageId) { msg in
                    msg.isStreaming = false
                    msg.wasStoppedByUser = true
                }
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
            isStreamingActive = false
            activeStreamTask = nil
        }

        activeStreamTask = streamTask
        await streamTask.value
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
