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
    var pendingInputText: String?
    var streamingScrollToken: UInt = 0

    private var activeStreamTask: Task<Void, Never>?

    private var settings = AppSettings.shared
    private let conversationManager = ConversationManager.shared
    @ObservationIgnored private let contextService: any WheelModelContextServing

    private let bufferFlusher = MarkdownBufferFlusher()

    private struct ConversationSnapshot {
        var messages: [ChatMessage]
        var lastFailedContent: String?
        var lastFailedPageContexts: [PageContext]
        var pageContextsByUserMessageId: [UUID: [PageContext]]
    }

    private var snapshots: [UUID: ConversationSnapshot] = [:]
    private(set) var activeConversationId: UUID?
    private var pageContextsByUserMessageId: [UUID: [PageContext]] = [:]
    private var lastFailedContent: String?
    private var lastFailedPageContexts: [PageContext] = []

    private var systemPrompt: String {
        SystemPromptConfig.chatPrompt
    }

    init(
        contextService: any WheelModelContextServing = WheelModelContextService.shared
    ) {
        self.contextService = contextService
    }

    func switchConversation(to conversationId: UUID) {
        guard conversationId != activeConversationId else { return }

        if let currentId = activeConversationId {
            snapshots[currentId] = ConversationSnapshot(
                messages: messages,
                lastFailedContent: lastFailedContent,
                lastFailedPageContexts: lastFailedPageContexts,
                pageContextsByUserMessageId: pageContextsByUserMessageId
            )
        }

        activeConversationId = conversationId
        let conversation = conversationManager.activateConversation(id: conversationId)

        if let snapshot = snapshots[conversationId] {
            messages = snapshot.messages
            lastFailedContent = snapshot.lastFailedContent
            lastFailedPageContexts = snapshot.lastFailedPageContexts
            pageContextsByUserMessageId = snapshot.pageContextsByUserMessageId
        } else {
            messages = conversation.messages
            lastFailedContent = nil
            lastFailedPageContexts = []
            pageContextsByUserMessageId = [:]
        }
    }

    func clearSnapshot(for conversationId: UUID) {
        snapshots.removeValue(forKey: conversationId)
    }

    private func safeUpdateMessage(id: UUID, update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
    }

    func sendMessage(_ content: String, pageContexts: [PageContext]) async {
        isLoading = true
        lastFailedPageContexts = pageContexts

        let fullMessage = ConversationHistoryBuilder.buildFullMessage(
            content: content,
            pageContexts: pageContexts
        )
        let contextBadges = ChatContextBadge.deduplicated(pageContexts.map(\.contextBadge))

        do {
            try await prepareActiveConversationThread(replaceExisting: false)
        } catch {
            self.error = error.localizedDescription
        }

        await sendMessageInternal(
            content: content,
            fullMessage: fullMessage,
            pageContexts: pageContexts,
            contextBadges: contextBadges
        )
    }

    func sendMessage(_ content: String, pageContext: PageContext? = nil) async {
        if let context = pageContext {
            await sendMessage(content, pageContexts: [context])
        } else {
            await sendMessage(content, pageContexts: [])
        }
    }

    func retryLastFailedMessage() async {
        guard let content = lastFailedContent else { return }

        if let lastMsg = messages.last, lastMsg.isFailed {
            messages.removeLast()
            syncConversationMessages()
        }

        let contexts = lastFailedPageContexts
        lastFailedContent = nil
        lastFailedPageContexts = []

        await sendMessage(content, pageContexts: contexts)
    }

    func stopGeneration() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isStreamingActive = false

        if let lastIdx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[lastIdx].isStreaming = false
            messages[lastIdx].wasStoppedByUser = true
        }

        if let thinkIdx = messages.lastIndex(where: { $0.role == .thinking && $0.isStreaming }) {
            messages[thinkIdx].isStreaming = false
        }

        syncConversationMessages()
        isLoading = false
    }

    func editAndResend(messageID: UUID, newContent: String, pageContexts: [PageContext]) async {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let originalMessage = messages[messageIndex]
        let effectivePageContexts = pageContexts.isEmpty
            ? (pageContextsByUserMessageId[messageID] ?? [])
            : pageContexts
        let contextBadges = originalMessage.contextBadges
            ?? ChatContextBadge.deduplicated(effectivePageContexts.map(\.contextBadge))
        let fullMessage = ConversationHistoryBuilder.buildFullMessage(
            content: newContent,
            pageContexts: effectivePageContexts
        )

        messages = ConversationBranchManager.editMessage(
            at: messageIndex,
            newContent: newContent,
            in: messages
        )

        guard let editedMessageId = messages.last?.id else {
            return
        }

        safeUpdateMessage(id: editedMessageId) { message in
            message.contextBadges = contextBadges
            message.modelContent = fullMessage
            message.modelUsed = "Apple Intelligence"
        }

        if effectivePageContexts.isEmpty {
            pageContextsByUserMessageId.removeValue(forKey: editedMessageId)
        } else {
            pageContextsByUserMessageId[editedMessageId] = effectivePageContexts
        }

        syncConversationMessages()
        do {
            try await prepareActiveConversationThread(
                excludingPendingUserMessageID: editedMessageId,
                replaceExisting: true
            )
        } catch {
            self.error = error.localizedDescription
        }

        await performStreaming(
            prompt: fullMessage,
            contextBadges: contextBadges
        )
    }

    func regenerateResponse(messageID: UUID? = nil) async {
        let targetIndex: Int?
        if let id = messageID {
            targetIndex = messages.firstIndex(where: { $0.id == id })
        } else {
            targetIndex = messages.lastIndex(where: { $0.role == .assistant })
        }
        guard let idx = targetIndex else { return }

        let userMessageIndex = messages[..<idx].lastIndex(where: { $0.role == .user })
        guard let userIdx = userMessageIndex else { return }

        let userMessage = messages[userIdx]
        let pageContexts = pageContextsByUserMessageId[userMessage.id] ?? []
        let contextBadges = userMessage.contextBadges
            ?? ChatContextBadge.deduplicated(pageContexts.map(\.contextBadge))
        let prompt = userMessage.modelContent ?? ConversationHistoryBuilder.buildFullMessage(
            content: userMessage.content,
            pageContexts: pageContexts
        )

        messages = ConversationBranchManager.regenerateResponse(at: idx, in: messages)
        syncConversationMessages()
        lastFailedPageContexts = pageContexts

        do {
            try await prepareActiveConversationThread(
                excludingPendingUserMessageID: userMessage.id,
                replaceExisting: true
            )
        } catch {
            self.error = error.localizedDescription
        }

        await performStreaming(
            prompt: prompt,
            contextBadges: contextBadges
        )
    }

    private func sendMessageInternal(
        content: String,
        fullMessage: String,
        pageContexts: [PageContext],
        contextBadges: [ChatContextBadge]
    ) async {
        isLoading = true
        isStreamingActive = true
        lastFailedContent = content

        let conversation = ensureActiveConversation()
        let userMessage = ChatMessage(
            role: .user,
            content: content,
            modelContent: fullMessage,
            timestamp: Date(),
            modelUsed: "Apple Intelligence",
            conversationId: conversation.id,
            contextBadges: contextBadges.isEmpty ? nil : contextBadges
        )
        messages.append(userMessage)

        if pageContexts.isEmpty {
            pageContextsByUserMessageId.removeValue(forKey: userMessage.id)
        } else {
            pageContextsByUserMessageId[userMessage.id] = pageContexts
        }

        conversationManager.addMessage(userMessage)
        await performStreaming(prompt: fullMessage, contextBadges: contextBadges)
    }

    private func performStreaming(
        prompt: String,
        contextBadges: [ChatContextBadge]
    ) async {
        isLoading = true
        isStreamingActive = true

        let assistantPlaceholder = ChatMessage(
            role: .assistant,
            content: "",
            timestamp: Date(),
            isStreaming: true,
            contextBadges: contextBadges.isEmpty ? nil : contextBadges
        )
        let assistantMessageId = assistantPlaceholder.id
        messages.append(assistantPlaceholder)

        let conversationID = activeConversationId
        let streamTask: Task<Void, Never> = Task { @MainActor in
            do {
                guard let conversationID else {
                    throw AgentError.invalidLLMResponse("No active conversation")
                }

                let stream = try await contextService.streamChatResponse(
                    conversationId: conversationID,
                    prompt: prompt
                )

                var latestResponse: LMManagedStructuredResponse<GeneratedChatAssistantResponse>?
                var latestAnswer = ""
                var lastStreamedAnswer = ""
                var pendingChunk = ""
                var lastUpdateTime = Date()
                let maxUpdateInterval: TimeInterval = WindowConstants.streamingFlushInterval

                for try await event in stream {
                    try Task.checkCancellation()

                    switch event {
                    case .partial(let currentAnswer):
                        let now = Date()
                        let timeSinceUpdate = now.timeIntervalSince(lastUpdateTime)
                        latestAnswer = currentAnswer

                        if currentAnswer.count > lastStreamedAnswer.count {
                            pendingChunk += String(currentAnswer.dropFirst(lastStreamedAnswer.count))
                        } else if currentAnswer != lastStreamedAnswer {
                            pendingChunk = currentAnswer
                        }
                        lastStreamedAnswer = currentAnswer

                        if bufferFlusher.shouldFlush(pendingChunk) || timeSinceUpdate >= maxUpdateInterval {
                            pendingChunk = ""
                            safeUpdateMessage(id: assistantMessageId) { $0.content = latestAnswer }
                            streamingScrollToken &+= 1
                            lastUpdateTime = now
                        }
                    case .completed(let response):
                        latestResponse = response
                        latestAnswer = response.content.answer
                    }
                }

                guard let latestResponse else {
                    throw AgentError.invalidLLMResponse("Structured chat response stream produced no content")
                }

                let displayContent = latestResponse.content.answer
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let followUps = FollowUpSuggestionNormalizer.normalize(
                    latestResponse.content.suggestions
                )
                let artifacts = ArtifactExtractor.extract(from: displayContent)

                safeUpdateMessage(id: assistantMessageId) { msg in
                    msg.content = displayContent
                    msg.isStreaming = false
                    msg.modelUsed = "Apple Intelligence"
                    msg.suggestedFollowUps = followUps
                    msg.artifacts = artifacts
                }

                syncConversationMessages()
                lastFailedContent = nil
                lastFailedPageContexts = []
            } catch is CancellationError {
                safeUpdateMessage(id: assistantMessageId) { msg in
                    msg.isStreaming = false
                    msg.wasStoppedByUser = true
                }
                syncConversationMessages()
            } catch {
                safeUpdateMessage(id: assistantMessageId) { msg in
                    msg.content = "Error: \(error.localizedDescription)"
                    msg.isStreaming = false
                    msg.isFailed = true
                }
                syncConversationMessages()
            }

            isLoading = false
            isStreamingActive = false
            activeStreamTask = nil
        }

        activeStreamTask = streamTask
        await streamTask.value
    }

    private func prepareActiveConversationThread(
        excludingPendingUserMessageID: UUID? = nil,
        replaceExisting: Bool
    ) async throws {
        guard let conversationId = activeConversationId else {
            return
        }

        let threadID = WheelModelContextService.chatThreadID(for: conversationId)
        let filteredMessages = modelVisibleMessages(excludingPendingUserMessageID: excludingPendingUserMessageID)
        let turns = filteredMessages.map { Self.normalizedTurn(from: $0) }
        let threadExists = (try? await contextService.threadState(threadID: threadID)) != nil

        if replaceExisting {
            try await contextService.importChatThread(
                conversationId: conversationId,
                instructions: systemPrompt,
                turns: turns,
                durableMemory: [],
                replaceExisting: true
            )
        } else if !threadExists && !turns.isEmpty {
            try await contextService.importChatThread(
                conversationId: conversationId,
                instructions: systemPrompt,
                turns: turns,
                durableMemory: [],
                replaceExisting: false
            )
        }

        try await contextService.openChatThread(
            conversationId: conversationId,
            instructions: systemPrompt
        )
    }

    private func modelVisibleMessages(excludingPendingUserMessageID: UUID?) -> [ChatMessage] {
        messages.filter { message in
            guard !message.isStreaming else {
                return false
            }
            guard message.id != excludingPendingUserMessageID else {
                return false
            }
            switch message.role {
            case .user, .assistant, .system:
                return true
            case .thinking:
                return false
            }
        }
    }

    private static func normalizedTurn(from message: ChatMessage) -> LMNormalizedTurn {
        let role: LMNormalizedTurn.Role
        let priority: Int

        switch message.role {
        case .user:
            role = .user
            priority = 950
        case .assistant:
            role = .assistant
            priority = 800
        case .system:
            role = .system
            priority = 700
        case .thinking:
            role = .system
            priority = 600
        }

        let text = message.role == .user ? (message.modelContent ?? message.content) : message.content
        return LMNormalizedTurn(
            id: message.id,
            role: role,
            text: text,
            createdAt: message.timestamp,
            priority: priority,
            windowIndex: 0
        )
    }

    private func ensureActiveConversation() -> Conversation {
        if let activeConversationId {
            return conversationManager.activateConversation(id: activeConversationId)
        }

        let conversation = conversationManager.startConversation()
        activeConversationId = conversation.id
        return conversation
    }

    private func syncConversationMessages() {
        guard let activeConversationId else { return }
        conversationManager.replaceMessages(messages, conversationID: activeConversationId)
    }

    func clearMessages() {
        if let activeConversationId {
            let threadID = WheelModelContextService.chatThreadID(for: activeConversationId)
            Task {
                try? await contextService.resetThread(threadID: threadID)
            }
        }

        conversationManager.saveCurrentConversation()
        conversationManager.clearCurrentConversation()
        messages.removeAll()
        lastFailedContent = nil
        lastFailedPageContexts = []
        pageContextsByUserMessageId.removeAll()

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
    let contextBadge: ChatContextBadge

    init(
        url: String,
        title: String,
        textContent: String,
        contextBadge: ChatContextBadge? = nil
    ) {
        self.url = url
        self.title = title
        self.textContent = textContent
        self.contextBadge = contextBadge ?? .website(title: title, url: url)
    }
}
