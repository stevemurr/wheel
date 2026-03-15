import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("AgentManager")
struct AgentManagerTests {
    @Test("Maps LM generation failures to a readable message")
    func mapsGenerationFailures() {
        let message = AgentManager.userFacingErrorMessage(
            for: RuntimeError.generationFailed("Streaming finished without completion")
        )

        #expect(message == "Streaming finished without completion")
    }

    @Test("Maps LM budget failures to context guidance")
    func mapsBudgetFailures() {
        let diagnosticsData = """
        {
          "sessionID": "chat-thread",
          "windowIndex": 0,
          "lastBudget": null,
          "lastCompaction": null,
          "lastBridge": null,
          "turnCount": 12,
          "durableMemoryCount": 0,
          "blobCount": 0
        }
        """.data(using: .utf8)!
        let diagnostics = try! JSONDecoder().decode(SessionDiagnostics.self, from: diagnosticsData)

        let message = AgentManager.userFacingErrorMessage(
            for: ContextManagerError.budgetExhausted(diagnostics)
        )

        #expect(message == "The chat ran out of context budget. Start a new conversation or remove some attached context.")
    }

    @Test("First message streams with empty history")
    func firstMessageStreamsWithEmptyHistory() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService()
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("Hello there", pageContexts: [])

        let streamCalls = await contextService.streamCalls()
        let thinkingMessages = manager.messages.filter { $0.role == .thinking }

        #expect(streamCalls.count == 1)
        #expect(streamCalls[0].history.isEmpty)
        #expect(streamCalls[0].prompt == "Hello there")
        #expect(await contextService.structuredStreamCallCount() == 1)
        #expect(manager.error == nil)
        #expect(manager.messages.count == 3)
        #expect(thinkingMessages.count == 1)
        #expect(thinkingMessages.first?.isStreaming == false)
        #expect(thinkingMessages.first?.thinkingDurationSeconds != nil)
        #expect(manager.messages.last?.content == "Hi there")
        #expect(manager.messages.last?.isFailed == false)
    }

    @Test("Structured chat suggestions populate follow-up pills")
    func structuredChatSuggestionsPopulateFollowUps() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService(
            responses: [
                GeneratedChatAssistantResponse(
                    answer: "Here is a fuller answer with details.",
                    suggestions: [
                        "First follow-up?",
                        "Second follow-up?",
                    ]
                )
            ]
        )
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("Explain this in more detail", pageContexts: [])

        #expect(await contextService.structuredStreamCallCount() == 1)
        #expect(manager.messages.count == 3)
        #expect(manager.messages[1].role == .thinking)
        #expect(manager.messages.last?.content == "Here is a fuller answer with details.")
        #expect(manager.messages.last?.suggestedFollowUps == [
            "First follow-up?",
            "Second follow-up?",
        ])
    }

    @Test("Structured chat fills thinking row with reasoning trace and tool calls")
    func structuredChatFillsThinkingRow() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService(
            responses: [
                GeneratedChatAssistantResponse(
                    answer: "The result is ready.",
                    thinking: "I compared the current page context with the user request before answering.",
                    toolCalls: [
                        GeneratedChatToolCall(
                            name: "web.search",
                            inputSummary: "site:example.com release notes",
                            outputSummary: "Found the latest release notes page."
                        )
                    ]
                )
            ]
        )
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("What changed?", pageContexts: [])

        #expect(manager.messages.count == 3)
        #expect(manager.messages[1].role == .thinking)
        #expect(manager.messages[1].content.contains("I compared the current page context") == true)
        #expect(manager.messages[1].content.contains("Tools used:") == true)
        #expect(manager.messages[1].content.contains("web.search") == true)
    }

    @Test("Streaming reasoning events populate the thinking row before completion")
    func streamingReasoningEventsPopulateThinkingRow() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService(
            streamedThinking: "Checking the user request against the available context."
        )
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("What changed?", pageContexts: [])

        #expect(manager.messages.count == 3)
        #expect(manager.messages[1].role == .thinking)
        #expect(manager.messages[1].content.contains("Checking the user request") == true)
        #expect(manager.messages[1].isStreaming == false)
    }

    @Test("Plain chat preserves injected page context in the stored user turn")
    func plainChatPreservesInjectedPageContext() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService()
        let manager = AgentManager(contextService: contextService)
        let pageContext = PageContext(
            url: "https://example.com",
            title: "Example",
            textContent: "Example body text"
        )

        await manager.sendMessage("What changed?", pageContexts: [pageContext])

        #expect(await contextService.structuredStreamCallCount() == 1)
        #expect(manager.messages.first?.content == "What changed?")
        #expect(manager.messages.first?.modelContent == """
        [Page Context]
        URL: https://example.com
        Title: Example
        Content Preview:
        Example body text

        [User Question]
        What changed?
        """)
    }

    @Test("Follow-up turns send the visible transcript directly")
    func followUpTurnsSendVisibleTranscriptDirectly() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService(
            responses: [
                GeneratedChatAssistantResponse(answer: "First answer"),
                GeneratedChatAssistantResponse(answer: "Second answer"),
            ]
        )
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("First question", pageContexts: [])
        await manager.sendMessage("Follow-up question", pageContexts: [])

        let streamCalls = await contextService.streamCalls()
        #expect(streamCalls.count == 2)
        #expect(streamCalls[1].history.map(\.role) == [.user, .assistant])
        #expect(streamCalls[1].history.map(\.text) == ["First question", "First answer"])
        #expect(manager.error == nil)
        #expect(manager.messages.count == 6)
        #expect(manager.messages.last?.content == "Second answer")
        #expect(manager.messages.last?.isFailed == false)
    }

    @Test("Follow-up formatting requests retain injected context from the previous turn")
    func followUpFormattingRequestsRetainInjectedContext() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let pageContext = PageContext(
            url: "note://estate-attorneys",
            title: "Estate Attorneys",
            textContent: "Richard A. Brouillet, Attorney at Law\nCamelia Mahmoudi, Law Office of Camelia Mahmoudi"
        )
        let expectedFirstTurn = """
        [Page Context]
        URL: note://estate-attorneys
        Title: Estate Attorneys
        Content Preview:
        Richard A. Brouillet, Attorney at Law
        Camelia Mahmoudi, Law Office of Camelia Mahmoudi

        [User Question]
        What attorneys are listed?
        """
        let firstAnswer = "You have two attorneys listed: Richard A. Brouillet and Camelia Mahmoudi."
        let contextService = RecordingChatContextService(
            responses: [
                GeneratedChatAssistantResponse(answer: firstAnswer),
                GeneratedChatAssistantResponse(answer: "Rendered table"),
            ]
        )
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("What attorneys are listed?", pageContexts: [pageContext])
        await manager.sendMessage("please list them in a table", pageContexts: [])

        let streamCalls = await contextService.streamCalls()
        #expect(streamCalls.count == 2)
        #expect(streamCalls[1].history.map(\.text) == [
            expectedFirstTurn,
            firstAnswer,
        ])
        #expect(streamCalls[1].prompt == "please list them in a table")
        #expect(manager.error == nil)
        #expect(manager.messages.last?.content == "Rendered table")
        #expect(manager.messages.last?.isFailed == false)
    }

    @Test("Missing thread errors surface without a hidden-session retry")
    func missingThreadErrorsSurfaceWithoutAHiddenSessionRetry() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService(failureAtAttempt: 1)
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("Hello again", pageContexts: [])

        #expect(await contextService.structuredStreamCallCount() == 1)
        #expect(manager.messages.count == 3)
        #expect(manager.messages[1].role == .thinking)
        #expect(manager.messages.last?.content == "Error: The chat thread could not be found. Starting a new conversation should fix it.")
        #expect(manager.messages.last?.isFailed == true)
    }
}

private actor RecordingChatContextService: WheelModelContextServing {
    struct StreamCall: Sendable, Equatable {
        let instructions: String
        let history: [WheelConversationTurn]
        let prompt: String
    }

    private var streamCallsStorage: [StreamCall] = []
    private let responses: [GeneratedChatAssistantResponse]
    private let streamedThinking: String?
    private let failureAtAttempt: Int?

    init(
        responses: [GeneratedChatAssistantResponse] = [
            GeneratedChatAssistantResponse(answer: "Hi there")
        ],
        streamedThinking: String? = nil,
        failureAtAttempt: Int? = nil
    ) {
        self.responses = responses
        self.streamedThinking = streamedThinking
        self.failureAtAttempt = failureAtAttempt
    }

    func availabilityStatus() async -> WheelModelAvailability {
        WheelModelAvailability(
            profile: WheelModelConfigurationProvider.shared.currentProfile(),
            runtimeAvailability: RuntimeAvailability(status: .available)
        )
    }

    func streamPlainChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        _ = instructions
        _ = history
        _ = prompt
        fatalError("Plain-text chat should not be used in AgentManagerTests")
    }

    func streamChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        let attempt = streamCallsStorage.count + 1
        streamCallsStorage.append(
            StreamCall(
                instructions: instructions,
                history: history,
                prompt: prompt
            )
        )

        if failureAtAttempt == attempt {
            throw ContextManagerError.threadNotFound("missing-thread")
        }

        let responseIndex = min(attempt - 1, responses.count - 1)
        let response = responses[responseIndex]
        let reply = WheelGeneratedReply(
            value: response,
            transcriptText: response.answer,
            metadata: WheelTurnMetadata(truncation: nil),
            modelDisplayName: WheelModelConfigurationProvider.shared.currentProfile().displayName
        )

        return AsyncThrowingStream { continuation in
            if let streamedThinking {
                continuation.yield(.thinking(trace: streamedThinking))
            }
            continuation.yield(.partial(answer: String(response.answer.prefix(2))))
            continuation.yield(.completed(reply))
            continuation.finish()
        }
    }

    func generateSettingsRouteDecision(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        _ = instructions
        _ = history
        _ = prompt
        fatalError("Not used in AgentManagerTests")
    }

    func generateSettingsPlan(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        _ = instructions
        _ = history
        _ = prompt
        fatalError("Not used in AgentManagerTests")
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        _ = tabId
        _ = runId
        _ = instructions
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        _ = requestID
        _ = task
        _ = instructions
        fatalError("Not used in AgentManagerTests")
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        _ = prompt
        _ = sessionID
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        _ = requestID
        _ = prompt
        _ = instructions
        fatalError("Not used in AgentManagerTests")
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        _ = text
        _ = tags
        _ = sessionID
        fatalError("Not used in AgentManagerTests")
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        _ = requestID
        _ = prompt
        _ = instructions
        fatalError("Not used in AgentManagerTests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        _ = requestID
        _ = prompt
        _ = instructions
        fatalError("Not used in AgentManagerTests")
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        _ = requestID
        _ = prompt
        _ = instructions
        _ = transcriptRenderer
        fatalError("Not used in AgentManagerTests")
    }

    func sessionExists(sessionID: String) async -> Bool {
        _ = sessionID
        return false
    }

    func resetSession(sessionID: String) async throws {
        _ = sessionID
    }

    func streamCalls() -> [StreamCall] {
        streamCallsStorage
    }

    func structuredStreamCallCount() -> Int {
        streamCallsStorage.count
    }
}
