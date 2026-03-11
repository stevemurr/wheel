import Foundation
import LanguageModelContextManagement
import Testing
@testable import WheelBrowser

@MainActor
@Suite("SettingsAssistantOrchestrator", .serialized)
struct SettingsAssistantOrchestratorTests {
    @Test("Settings report requests stay on Apple")
    func settingsReportRequestsStayOnApple() async throws {
        let apple = MockSettingsAssistantContextService(
            availability: .available,
            routeDecision: GeneratedSettingsRouteDecision(
                route: SettingsAssistantRoute.settingsReport.rawValue,
                reason: "The user asked to inspect a supported setting.",
                confidence: 0.99,
                mentionedSettingIDs: ["ai.provider"]
            ),
            settingsPlan: GeneratedSettingsPlan(
                reply: "You are using Apple for AI chat.",
                warnings: [],
                actions: [],
                requiresConfirmation: false
            )
        )
        let general = MockSettingsAssistantContextService(availability: .available)
        let orchestrator = SettingsAssistantOrchestrator(
            appleContextService: apple,
            generalContextService: general,
            registry: .shared
        )

        let result = try await orchestrator.prepareTurn(
            prompt: "What model am I using?",
            visibleMessages: [
                ChatMessage.user("Earlier question"),
                ChatMessage.assistant("Earlier answer")
            ],
            settingsConversationID: UUID(),
            generalConversationID: UUID()
        )

        guard case .reply(let reply) = result else {
            Issue.record("Expected an immediate Apple settings reply")
            return
        }

        #expect(reply.source == .appleSettings)
        #expect(reply.pendingPlan == nil)
        #expect(reply.message.contains("Apple"))
        #expect(await apple.importCallCount() == 2)
        #expect(await general.importCallCount() == 0)
    }

    @Test("Settings mutation requests produce a pending confirmation only")
    func settingsMutationRequestsProducePendingConfirmation() async throws {
        let apple = MockSettingsAssistantContextService(
            availability: .available,
            routeDecision: GeneratedSettingsRouteDecision(
                route: SettingsAssistantRoute.settingsMutation.rawValue,
                reason: "The user asked to change a supported setting.",
                confidence: 0.98,
                mentionedSettingIDs: ["semanticSearch.enabled"]
            ),
            settingsPlan: GeneratedSettingsPlan(
                reply: "I can turn Semantic Search on.",
                warnings: ["This reinitializes the local search backend."],
                actions: [
                    GeneratedSettingsAction(
                        actionType: SettingsAssistantActionType.setBool.rawValue,
                        settingID: "semanticSearch.enabled",
                        boolValue: true,
                        stringValue: nil,
                        intValue: nil,
                        doubleValue: nil,
                        enumValue: nil
                    )
                ],
                requiresConfirmation: true
            )
        )
        let general = MockSettingsAssistantContextService(availability: .available)
        let orchestrator = SettingsAssistantOrchestrator(
            appleContextService: apple,
            generalContextService: general,
            registry: .shared
        )

        let result = try await orchestrator.prepareTurn(
            prompt: "Turn on semantic search",
            visibleMessages: [],
            settingsConversationID: UUID(),
            generalConversationID: UUID()
        )

        guard case .reply(let reply) = result else {
            Issue.record("Expected a planned settings reply")
            return
        }

        #expect(reply.pendingPlan?.actions.count == 1)
        #expect(reply.message.contains("Confirm to apply"))
        #expect(await general.streamCallCount() == 0)
    }

    @Test("General chat uses configured model when it is available")
    func generalChatUsesConfiguredModelWhenAvailable() async throws {
        let apple = MockSettingsAssistantContextService(
            availability: .available,
            routeDecision: GeneratedSettingsRouteDecision(
                route: SettingsAssistantRoute.generalChat.rawValue,
                reason: "This is a normal chat question.",
                confidence: 0.95,
                mentionedSettingIDs: []
            )
        )
        let general = MockSettingsAssistantContextService(
            availability: .available,
            streamedReply: WheelGeneratedReply(
                value: GeneratedChatAssistantResponse(answer: "General answer", suggestions: []),
                transcriptText: "General answer",
                metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
                modelDisplayName: "OpenAI / gpt-4.1-mini"
            )
        )
        let orchestrator = SettingsAssistantOrchestrator(
            appleContextService: apple,
            generalContextService: general,
            registry: .shared
        )

        let result = try await orchestrator.prepareTurn(
            prompt: "Explain what a context window is.",
            visibleMessages: [ChatMessage.user("Earlier prompt")],
            settingsConversationID: UUID(),
            generalConversationID: UUID()
        )

        guard case .generalChat(_, let source) = result else {
            Issue.record("Expected a streamed general chat route")
            return
        }

        #expect(source == .configuredGeneralChat)
        #expect(await general.importCallCount() == 1)
        #expect(await general.streamCallCount() == 1)
        #expect(await apple.importCallCount() == 1)
    }

    @Test("General chat falls back to Apple when configured model is unavailable")
    func generalChatFallsBackToApple() async throws {
        let apple = MockSettingsAssistantContextService(
            availability: .available,
            routeDecision: GeneratedSettingsRouteDecision(
                route: SettingsAssistantRoute.generalChat.rawValue,
                reason: "This is a normal chat question.",
                confidence: 0.93,
                mentionedSettingIDs: []
            ),
            streamedReply: WheelGeneratedReply(
                value: GeneratedChatAssistantResponse(answer: "Apple fallback answer", suggestions: []),
                transcriptText: "Apple fallback answer",
                metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
                modelDisplayName: "Apple / default"
            )
        )
        let general = MockSettingsAssistantContextService(
            availability: .unavailable("Configured model unavailable")
        )
        let orchestrator = SettingsAssistantOrchestrator(
            appleContextService: apple,
            generalContextService: general,
            registry: .shared
        )

        let result = try await orchestrator.prepareTurn(
            prompt: "Tell me a joke.",
            visibleMessages: [],
            settingsConversationID: UUID(),
            generalConversationID: UUID()
        )

        guard case .generalChat(_, let source) = result else {
            Issue.record("Expected a streamed fallback route")
            return
        }

        #expect(source == .appleGeneralFallback)
        #expect(await apple.importCallCount() == 2)
        #expect(await apple.streamCallCount() == 1)
        #expect(await general.importCallCount() == 0)
    }

    @Test("Alternating settings and general turns reimport the visible transcript")
    func alternatingTurnsReimportVisibleTranscript() async throws {
        let settingsConversationID = UUID()
        let generalConversationID = UUID()
        let apple = MockSettingsAssistantContextService(
            availability: .available,
            routeDecisions: [
                GeneratedSettingsRouteDecision(
                    route: SettingsAssistantRoute.settingsReport.rawValue,
                    reason: "Inspect a supported setting.",
                    confidence: 0.99,
                    mentionedSettingIDs: ["ai.provider"]
                ),
                GeneratedSettingsRouteDecision(
                    route: SettingsAssistantRoute.generalChat.rawValue,
                    reason: "This is normal chat.",
                    confidence: 0.91,
                    mentionedSettingIDs: []
                )
            ],
            settingsPlans: [
                GeneratedSettingsPlan(
                    reply: "You are using Apple.",
                    warnings: [],
                    actions: [],
                    requiresConfirmation: false
                )
            ],
            streamedReply: WheelGeneratedReply(
                value: GeneratedChatAssistantResponse(answer: "Fallback answer", suggestions: []),
                transcriptText: "Fallback answer",
                metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
                modelDisplayName: "Apple / default"
            )
        )
        let general = MockSettingsAssistantContextService(
            availability: .available,
            streamedReply: WheelGeneratedReply(
                value: GeneratedChatAssistantResponse(answer: "Configured answer", suggestions: []),
                transcriptText: "Configured answer",
                metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
                modelDisplayName: "OpenAI / gpt-4.1-mini"
            )
        )
        let orchestrator = SettingsAssistantOrchestrator(
            appleContextService: apple,
            generalContextService: general,
            registry: .shared
        )

        _ = try await orchestrator.prepareTurn(
            prompt: "What provider am I using?",
            visibleMessages: [
                ChatMessage.user("Hi"),
                ChatMessage.assistant("Hello")
            ],
            settingsConversationID: settingsConversationID,
            generalConversationID: generalConversationID
        )

        _ = try await orchestrator.prepareTurn(
            prompt: "Explain why local models are useful.",
            visibleMessages: [
                ChatMessage.user("Hi"),
                ChatMessage.assistant("Hello"),
                ChatMessage.user("What provider am I using?"),
                ChatMessage.assistant("You are using Apple.")
            ],
            settingsConversationID: settingsConversationID,
            generalConversationID: generalConversationID
        )

        let appleImports = await apple.importCalls()
        let generalImports = await general.importCalls()

        #expect(appleImports.count == 3)
        #expect(appleImports[0].turns.count == 2)
        #expect(appleImports[1].turns.count == 2)
        #expect(appleImports[2].turns.count == 4)
        #expect(generalImports.count == 1)
        #expect(generalImports[0].turns.count == 4)
        #expect(generalImports[0].conversationID == generalConversationID)
        #expect(generalImports[0].turns.last?.text == "You are using Apple.")
    }
}

private actor MockSettingsAssistantContextService: WheelModelContextServing {
    struct ImportCall: Sendable {
        let conversationID: UUID
        let instructions: String
        let turns: [WheelNormalizedTurn]
        let replaceExisting: Bool
    }

    enum Availability: Sendable {
        case available
        case unavailable(String)
    }

    private let availability: Availability
    private var routeDecisions: [GeneratedSettingsRouteDecision]
    private var settingsPlans: [GeneratedSettingsPlan]
    private let streamedReply: WheelGeneratedReply<GeneratedChatAssistantResponse>?
    private var importHistory: [ImportCall] = []
    private var streamCalls = 0

    init(
        availability: Availability,
        routeDecision: GeneratedSettingsRouteDecision? = nil,
        settingsPlan: GeneratedSettingsPlan? = nil,
        routeDecisions: [GeneratedSettingsRouteDecision] = [],
        settingsPlans: [GeneratedSettingsPlan] = [],
        streamedReply: WheelGeneratedReply<GeneratedChatAssistantResponse>? = nil
    ) {
        self.availability = availability
        self.routeDecisions = routeDecision.map { [$0] } ?? routeDecisions
        self.settingsPlans = settingsPlan.map { [$0] } ?? settingsPlans
        self.streamedReply = streamedReply
    }

    func availabilityStatus() async -> WheelModelAvailability {
        let runtimeAvailability: RuntimeAvailability
        switch availability {
        case .available:
            runtimeAvailability = RuntimeAvailability(status: .available)
        case .unavailable(let reason):
            runtimeAvailability = RuntimeAvailability(status: .unavailable(reason: reason))
        }

        return WheelModelAvailability(
            profile: WheelModelConfigurationProvider.shared.currentProfile(),
            runtimeAvailability: runtimeAvailability
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
        importHistory.append(
            ImportCall(
                conversationID: conversationId,
                instructions: instructions,
                turns: turns,
                replaceExisting: replaceExisting
            )
        )
    }

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        streamCalls += 1

        let reply = streamedReply ?? WheelGeneratedReply(
            value: GeneratedChatAssistantResponse(answer: "Fallback response", suggestions: []),
            transcriptText: "Fallback response",
            metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
            modelDisplayName: "Mock / default"
        )

        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(reply))
            continuation.finish()
        }
    }

    func streamPlainChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateSettingsRouteDecision(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        let value = routeDecisions.isEmpty
            ? GeneratedSettingsRouteDecision(
                route: SettingsAssistantRoute.unsupported.rawValue,
                reason: "No route configured for this test.",
                confidence: 1,
                mentionedSettingIDs: []
            )
            : routeDecisions.removeFirst()

        return WheelGeneratedReply(
            value: value,
            transcriptText: value.reason,
            metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
            modelDisplayName: "Apple / default"
        )
    }

    func generateSettingsPlan(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        let value = settingsPlans.isEmpty
            ? GeneratedSettingsPlan(reply: "No plan configured.", warnings: [], actions: [], requiresConfirmation: false)
            : settingsPlans.removeFirst()

        return WheelGeneratedReply(
            value: value,
            transcriptText: value.reply,
            metadata: WheelTurnMetadata(compaction: nil, bridge: nil),
            modelDisplayName: "Apple / default"
        )
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func sessionExists(sessionID: String) async -> Bool { true }

    func resetSession(sessionID: String) async throws {}

    func importCalls() -> [ImportCall] {
        importHistory
    }

    func importCallCount() -> Int {
        importHistory.count
    }

    func streamCallCount() -> Int {
        streamCalls
    }
}
