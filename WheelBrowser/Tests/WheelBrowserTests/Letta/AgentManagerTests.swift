import Foundation
import LanguageModelContextManagement
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

    @Test("First message opens a chat thread before streaming")
    func firstMessageOpensThreadBeforeStreaming() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService()
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("Hello there", pageContexts: [])

        let openedConversationIDs = await contextService.openedConversationIDs()
        let streamedConversationIDs = await contextService.streamedConversationIDs()

        #expect(openedConversationIDs.count == 1)
        #expect(streamedConversationIDs == openedConversationIDs)
        #expect(manager.error == nil)
        #expect(manager.messages.count == 2)
        #expect(manager.messages.last?.content == "Hi there")
        #expect(manager.messages.last?.isFailed == false)
    }

    @Test("Plain chat strips trailing follow-up sections into suggestion pills")
    func plainChatStripsTrailingFollowUps() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecordingChatContextService(
            responseText: """
            Here is a fuller answer with details.

            Follow-up questions:
            - First follow-up?
            - Second follow-up?
            """
        )
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("Explain this in more detail", pageContexts: [])

        #expect(await contextService.structuredStreamCallCount() == 0)
        #expect(await contextService.plainStreamCallCount() == 1)
        #expect(manager.messages.count == 2)
        #expect(manager.messages.last?.content == "Here is a fuller answer with details.")
        #expect(manager.messages.last?.suggestedFollowUps == [
            "First follow-up?",
            "Second follow-up?",
        ])
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

        #expect(await contextService.plainStreamCallCount() == 1)
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

    @Test("Follow-up turns resync transcript before streaming against an existing session")
    func followUpTurnsResyncTranscriptBeforeStreaming() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = TranscriptSyncRequiredChatContextService()
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("First question", pageContexts: [])
        await manager.sendMessage("Follow-up question", pageContexts: [])

        #expect(await contextService.importCount() == 1)
        #expect(await contextService.lastImportedTurnCount() == 2)
        #expect(await contextService.streamCallCount() == 2)
        #expect(manager.error == nil)
        #expect(manager.messages.count == 4)
        #expect(manager.messages.last?.content == "Second answer")
        #expect(manager.messages.last?.isFailed == false)
    }

    @Test("Missing chat thread during streaming rebuilds history and retries once")
    func missingThreadDuringStreamingRetriesWithImportedHistory() async {
        ConversationManager.shared.clearCurrentConversation()
        defer {
            ConversationManager.shared.clearCurrentConversation()
        }

        let contextService = RecoveringChatContextService()
        let manager = AgentManager(contextService: contextService)

        await manager.sendMessage("Hello again", pageContexts: [])

        #expect(await contextService.streamAttemptCount() == 2)
        #expect(await contextService.importCount() == 1)
        #expect(manager.error == nil)
        #expect(manager.messages.count == 2)
        #expect(manager.messages.last?.content == "Recovered reply")
        #expect(manager.messages.last?.isFailed == false)
    }
}

private actor TranscriptSyncRequiredChatContextService: WheelModelContextServing {
    private var importCalls = 0
    private var lastImportTurnCount = 0
    private var streamCalls = 0
    private var didImportTranscriptForFollowUp = false

    func availabilityStatus() async -> WheelModelAvailability {
        WheelModelAvailability(
            profile: WheelModelConfigurationProvider.shared.currentProfile(),
            runtimeAvailability: RuntimeAvailability(status: .available)
        )
    }

    func openChatSession(conversationId: UUID, instructions: String) async throws {}

    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [WheelNormalizedTurn],
        durableMemory: [WheelDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {
        importCalls += 1
        lastImportTurnCount = turns.count
        didImportTranscriptForFollowUp = replaceExisting && turns.count == 2
    }

    func streamPlainChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        streamCalls += 1

        if streamCalls == 2 && !didImportTranscriptForFollowUp {
            throw RuntimeError.generationFailed("Transcript was not synced before the follow-up turn")
        }

        let answer = streamCalls == 1 ? "First answer" : "Second answer"
        let reply = WheelGeneratedReply(
            value: answer,
            transcriptText: answer,
            metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
            modelDisplayName: WheelModelConfigurationProvider.shared.currentProfile().displayName
        )

        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(reply))
            continuation.finish()
        }
    }

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        fatalError("Structured chat should not be used in AgentManagerTests")
    }

    func generateSettingsRouteDecision(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateSettingsPlan(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        fatalError("Not used in AgentManagerTests")
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        fatalError("Not used in AgentManagerTests")
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        fatalError("Not used in AgentManagerTests")
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        fatalError("Not used in AgentManagerTests")
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        fatalError("Not used in AgentManagerTests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        fatalError("Not used in AgentManagerTests")
    }

    func sessionExists(sessionID: String) async -> Bool {
        true
    }

    func resetSession(sessionID: String) async throws {}

    func importCount() -> Int {
        importCalls
    }

    func lastImportedTurnCount() -> Int {
        lastImportTurnCount
    }

    func streamCallCount() -> Int {
        streamCalls
    }
}

private actor RecordingChatContextService: WheelModelContextServing {
    private var openedIDs: [UUID] = []
    private var streamedIDs: [UUID] = []
    private var plainStreamCalls = 0
    private var structuredStreamCalls = 0
    private let responseText: String

    init(responseText: String = "Hi there") {
        self.responseText = responseText
    }

    func availabilityStatus() async -> WheelModelAvailability {
        WheelModelAvailability(
            profile: WheelModelConfigurationProvider.shared.currentProfile(),
            runtimeAvailability: RuntimeAvailability(status: .available)
        )
    }

    func openChatSession(conversationId: UUID, instructions: String) async throws {
        openedIDs.append(conversationId)
    }

    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [WheelNormalizedTurn],
        durableMemory: [WheelDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {
        if openedIDs.contains(conversationId) == false {
            openedIDs.append(conversationId)
        }
    }

    func streamPlainChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        plainStreamCalls += 1
        streamedIDs.append(conversationId)

        guard openedIDs.contains(conversationId) else {
            throw ContextManagerError.threadNotFound(conversationId.uuidString)
        }

        let reply = WheelGeneratedReply(
            value: responseText,
            transcriptText: responseText,
            metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
            modelDisplayName: WheelModelConfigurationProvider.shared.currentProfile().displayName
        )

        return AsyncThrowingStream { continuation in
            continuation.yield(.partial(answer: String(responseText.prefix(2))))
            continuation.yield(.completed(reply))
            continuation.finish()
        }
    }

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        structuredStreamCalls += 1
        fatalError("Structured chat should not be used in AgentManagerTests")
    }

    func generateSettingsRouteDecision(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateSettingsPlan(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        fatalError("Not used in AgentManagerTests")
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        fatalError("Not used in AgentManagerTests")
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        fatalError("Not used in AgentManagerTests")
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        fatalError("Not used in AgentManagerTests")
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        fatalError("Not used in AgentManagerTests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        fatalError("Not used in AgentManagerTests")
    }

    func sessionExists(sessionID: String) async -> Bool {
        false
    }

    func resetSession(sessionID: String) async throws {}

    func openedConversationIDs() -> [UUID] {
        openedIDs
    }

    func streamedConversationIDs() -> [UUID] {
        streamedIDs
    }

    func plainStreamCallCount() -> Int {
        plainStreamCalls
    }

    func structuredStreamCallCount() -> Int {
        structuredStreamCalls
    }
}

private actor RecoveringChatContextService: WheelModelContextServing {
    private var streamAttempts = 0
    private var imports = 0
    private var importedHistory = false

    func availabilityStatus() async -> WheelModelAvailability {
        WheelModelAvailability(
            profile: WheelModelConfigurationProvider.shared.currentProfile(),
            runtimeAvailability: RuntimeAvailability(status: .available)
        )
    }

    func openChatSession(conversationId: UUID, instructions: String) async throws {}

    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [WheelNormalizedTurn],
        durableMemory: [WheelDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {
        imports += 1
        importedHistory = !turns.isEmpty
    }

    func streamPlainChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        streamAttempts += 1

        if streamAttempts == 1 {
            throw ContextManagerError.threadNotFound(conversationId.uuidString)
        }

        guard importedHistory else {
            throw ContextManagerError.threadNotFound(conversationId.uuidString)
        }

        let reply = WheelGeneratedReply(
            value: "Recovered reply",
            transcriptText: "Recovered reply",
            metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
            modelDisplayName: WheelModelConfigurationProvider.shared.currentProfile().displayName
        )

        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(reply))
            continuation.finish()
        }
    }

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        fatalError("Structured chat should not be used in AgentManagerTests")
    }

    func generateSettingsRouteDecision(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateSettingsPlan(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        fatalError("Not used in AgentManagerTests")
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        fatalError("Not used in AgentManagerTests")
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        fatalError("Not used in AgentManagerTests")
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        fatalError("Not used in AgentManagerTests")
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        fatalError("Not used in AgentManagerTests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        fatalError("Not used in AgentManagerTests")
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        fatalError("Not used in AgentManagerTests")
    }

    func sessionExists(sessionID: String) async -> Bool {
        true
    }

    func resetSession(sessionID: String) async throws {}

    func streamAttemptCount() -> Int {
        streamAttempts
    }

    func importCount() -> Int {
        imports
    }
}
