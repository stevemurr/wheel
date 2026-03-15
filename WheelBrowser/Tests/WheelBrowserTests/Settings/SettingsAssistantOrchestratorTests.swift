import Foundation
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
        #expect(await apple.routeCallCount() == 1)
        #expect(await apple.planCallCount() == 1)
        #expect(await general.streamCallCount() == 0)
        #expect(await apple.routeCalls().first?.history.count == 2)
        #expect(await apple.planCalls().first?.history.count == 2)
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
        #expect(await apple.routeCallCount() == 1)
        #expect(await apple.planCallCount() == 1)
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
                metadata: WheelTurnMetadata(truncation: nil),
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
        #expect(await apple.routeCallCount() == 1)
        #expect(await general.streamCallCount() == 1)
        #expect(await general.streamCalls().first?.history.map(\.text) == ["Earlier prompt"])
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
                metadata: WheelTurnMetadata(truncation: nil),
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
        #expect(await apple.routeCallCount() == 1)
        #expect(await apple.streamCallCount() == 1)
        #expect(await general.streamCallCount() == 0)
    }

    @Test("Alternating settings and general turns reuse the visible transcript directly")
    func alternatingTurnsReuseVisibleTranscriptDirectly() async throws {
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
            ]
        )
        let general = MockSettingsAssistantContextService(
            availability: .available,
            streamedReply: WheelGeneratedReply(
                value: GeneratedChatAssistantResponse(answer: "Configured answer", suggestions: []),
                transcriptText: "Configured answer",
                metadata: WheelTurnMetadata(truncation: nil),
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
            settingsConversationID: UUID(),
            generalConversationID: UUID()
        )

        _ = try await orchestrator.prepareTurn(
            prompt: "Explain why local models are useful.",
            visibleMessages: [
                ChatMessage.user("Hi"),
                ChatMessage.assistant("Hello"),
                ChatMessage.user("What provider am I using?"),
                ChatMessage.assistant("You are using Apple.")
            ],
            settingsConversationID: UUID(),
            generalConversationID: UUID()
        )

        let appleRouteCalls = await apple.routeCalls()
        let applePlanCalls = await apple.planCalls()
        let generalStreamCalls = await general.streamCalls()

        #expect(appleRouteCalls.count == 2)
        #expect(appleRouteCalls[0].history.count == 2)
        #expect(appleRouteCalls[1].history.count == 4)
        #expect(applePlanCalls.count == 1)
        #expect(applePlanCalls[0].history.count == 2)
        #expect(generalStreamCalls.count == 1)
        #expect(generalStreamCalls[0].history.count == 4)
        #expect(generalStreamCalls[0].history.last?.text == "You are using Apple.")
    }
}

private actor MockSettingsAssistantContextService: WheelModelContextServing {
    struct RouteCall: Sendable, Equatable {
        let instructions: String
        let history: [WheelConversationTurn]
        let prompt: String
    }

    struct PlanCall: Sendable, Equatable {
        let instructions: String
        let history: [WheelConversationTurn]
        let prompt: String
    }

    struct StreamCall: Sendable, Equatable {
        let instructions: String
        let history: [WheelConversationTurn]
        let prompt: String
    }

    enum Availability: Sendable {
        case available
        case unavailable(String)
    }

    private let availability: Availability
    private var routeDecisions: [GeneratedSettingsRouteDecision]
    private var settingsPlans: [GeneratedSettingsPlan]
    private let streamedReply: WheelGeneratedReply<GeneratedChatAssistantResponse>?
    private var routeCallStorage: [RouteCall] = []
    private var planCallStorage: [PlanCall] = []
    private var streamCallStorage: [StreamCall] = []

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

    func streamPlainChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        _ = instructions
        _ = history
        _ = prompt
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func streamChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        streamCallStorage.append(
            StreamCall(
                instructions: instructions,
                history: history,
                prompt: prompt
            )
        )

        let reply = streamedReply ?? WheelGeneratedReply(
            value: GeneratedChatAssistantResponse(answer: "Fallback response", suggestions: []),
            transcriptText: "Fallback response",
            metadata: WheelTurnMetadata(truncation: nil),
            modelDisplayName: "Mock / default"
        )

        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(reply))
            continuation.finish()
        }
    }

    func generateSettingsRouteDecision(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        routeCallStorage.append(
            RouteCall(
                instructions: instructions,
                history: history,
                prompt: prompt
            )
        )

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
            metadata: WheelTurnMetadata(truncation: nil),
            modelDisplayName: "Apple / default"
        )
    }

    func generateSettingsPlan(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        planCallStorage.append(
            PlanCall(
                instructions: instructions,
                history: history,
                prompt: prompt
            )
        )

        let value = settingsPlans.isEmpty
            ? GeneratedSettingsPlan(reply: "No plan configured.", warnings: [], actions: [], requiresConfirmation: false)
            : settingsPlans.removeFirst()

        return WheelGeneratedReply(
            value: value,
            transcriptText: value.reply,
            metadata: WheelTurnMetadata(truncation: nil),
            modelDisplayName: "Apple / default"
        )
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        _ = tabId
        _ = runId
        _ = instructions
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        _ = requestID
        _ = task
        _ = instructions
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        _ = prompt
        _ = sessionID
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        _ = requestID
        _ = prompt
        _ = instructions
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        _ = text
        _ = tags
        _ = sessionID
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        _ = requestID
        _ = prompt
        _ = instructions
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        _ = requestID
        _ = prompt
        _ = instructions
        fatalError("Not used in SettingsAssistantOrchestratorTests")
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
        fatalError("Not used in SettingsAssistantOrchestratorTests")
    }

    func sessionExists(sessionID: String) async -> Bool {
        _ = sessionID
        return false
    }

    func resetSession(sessionID: String) async throws {
        _ = sessionID
    }

    func routeCalls() -> [RouteCall] {
        routeCallStorage
    }

    func planCalls() -> [PlanCall] {
        planCallStorage
    }

    func streamCalls() -> [StreamCall] {
        streamCallStorage
    }

    func routeCallCount() -> Int {
        routeCallStorage.count
    }

    func planCallCount() -> Int {
        planCallStorage.count
    }

    func streamCallCount() -> Int {
        streamCallStorage.count
    }
}
