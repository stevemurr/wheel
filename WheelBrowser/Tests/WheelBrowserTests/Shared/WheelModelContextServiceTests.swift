import Foundation
import Testing
@testable import WheelBrowser

@Suite("WheelModelContextService")
struct WheelModelContextServiceTests {
    @Test("Session IDs are namespaced by surface")
    func sessionIDRouting() {
        let conversationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let tabID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let runID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let requestID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!

        #expect(
            WheelModelContextService.chatSessionID(for: conversationID)
                == "chat:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        #expect(
            WheelModelContextService.agentSessionID(tabId: tabID, runId: runID)
                == "agent:11111111-2222-3333-4444-555555555555:66666666-7777-8888-9999-aaaaaaaaaaaa"
        )
        #expect(
            WheelModelContextService.summarySessionID(for: requestID)
                == "summary:bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
        )
        #expect(
            WheelModelContextService.widgetSessionID(for: requestID)
                == "widget:bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
        )
    }

    @Test("vLLM uses streaming text compatibility")
    func vllmUsesStreamingTextCompatibility() {
        #expect(WheelModelContextService.usesStreamingTextCompatibility(for: .vllm))
        #expect(WheelModelContextService.usesStreamingTextCompatibility(for: .openAI))
        #expect(WheelModelContextService.usesStreamingTextCompatibility(for: .apple))
    }

    @Test("Unsupported text streaming errors are eligible for one-shot fallback")
    func unsupportedTextStreamingUsesFallback() {
        #expect(
            WheelModelContextService.isUnsupportedTextStreaming(
                RuntimeError.unsupportedCapability("streaming is unavailable")
            )
        )
        #expect(
            WheelModelContextService.isUnsupportedTextStreaming(
                RuntimeError.generationFailed("different failure")
            ) == false
        )
    }

    @Test("Agent sessions exist only in memory and can be reset")
    func agentSessionsExistOnlyInMemory() async throws {
        let service = makeService()
        let tabID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let runID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let sessionID = WheelModelContextService.agentSessionID(tabId: tabID, runId: runID)

        #expect(await service.sessionExists(sessionID: sessionID) == false)

        let openedSessionID = try await service.openAgentSession(
            tabId: tabID,
            runId: runID,
            instructions: "Use tools to browse and report results."
        )

        #expect(openedSessionID == sessionID)
        #expect(await service.sessionExists(sessionID: sessionID))

        try await service.resetSession(sessionID: sessionID)

        #expect(await service.sessionExists(sessionID: sessionID) == false)
    }

    @Test("Agent sessions preserve hidden turns across a run")
    func agentSessionsPreserveHiddenTurnsAcrossARun() async throws {
        let backendState = RecordingBackendState(
            responses: [
                #"{"thought":"Read the result list first.","action":{"actionType":"read_links"}}"#,
                #"{"thought":"Finish the task.","action":{"actionType":"done","summary":"Collected the attorneys."}}"#,
            ]
        )
        let service = makeService(backendState: backendState)
        let sessionID = try await service.openAgentSession(
            tabId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            runId: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            instructions: "Use tools to browse and report results."
        )

        try await service.appendAgentToolTurn(
            text: "Clicked the pagination link.",
            tags: ["tool", "pagination"],
            sessionID: sessionID
        )

        let firstStream = try await service.streamAgentDecision(
            prompt: "What should the agent do next?",
            sessionID: sessionID
        )
        for try await _ in firstStream {}

        let secondStream = try await service.streamAgentDecision(
            prompt: "Summarize progress.",
            sessionID: sessionID
        )
        for try await _ in secondStream {}

        let calls = await backendState.calls()
        #expect(calls.count == 2)
        #expect(calls[0].history.count == 1)
        #expect(calls[0].history[0].role == .system)
        #expect(calls[0].history[0].text == "Clicked the pagination link.")
        #expect(calls[0].history[0].tags == ["tool", "pagination"])
        #expect(calls[1].history.map(\.role) == [.system, .user, .assistant])
        #expect(calls[1].history.map(\.text) == [
            "Clicked the pagination link.",
            "What should the agent do next?",
            "Action: read_links",
        ])
        #expect(calls[1].prompt.contains("Summarize progress."))
    }

    @Test("Chat follow-ups send visible prior turns directly")
    func chatFollowUpsSendVisiblePriorTurnsDirectly() async throws {
        let backendState = RecordingBackendState(
            responses: [#"{"answer":"Rendered table"}"#]
        )
        let service = makeService(backendState: backendState)
        let noteQuestion = """
        [Page Context]
        URL: note://estate-attorneys
        Title: Estate Attorneys
        Content Preview:
        Richard A. Brouillet, Attorney at Law
        Camelia Mahmoudi, Law Office of Camelia Mahmoudi

        [User Question]
        What attorneys are listed?
        """
        let history = [
            WheelConversationTurn(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                role: .user,
                text: noteQuestion,
                createdAt: Date(timeIntervalSince1970: 1),
                priority: 950
            ),
            WheelConversationTurn(
                id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
                role: .assistant,
                text: "You have two attorneys listed: Richard A. Brouillet and Camelia Mahmoudi.",
                createdAt: Date(timeIntervalSince1970: 2),
                priority: 800
            )
        ]

        let stream = try await service.streamChatResponse(
            instructions: "Reply concisely.",
            history: history,
            prompt: "please list them in a table"
        )

        var completedAnswer: String?
        for try await event in stream {
            if case .completed(let reply) = event {
                completedAnswer = reply.value.answer
            }
        }

        let calls = await backendState.calls()
        #expect(calls.count == 1)
        #expect(calls[0].instructions == "Reply concisely.")
        #expect(calls[0].history == history)
        #expect(calls[0].prompt.contains("please list them in a table"))
        #expect(completedAnswer == "Rendered table")
    }

    @Test("OpenAI-compatible backends send role-separated message history")
    func openAICompatibleBackendsSendRoleSeparatedHistory() throws {
        let backend = WheelOpenAICompatibleBackend(
            backendID: WheelModelProviderID.openAI.rawValue,
            kind: .openAI
        )
        let endpoint = ModelEndpoint(
            backendID: WheelModelProviderID.openAI.rawValue,
            modelID: "gpt-4.1-mini",
            options: [
                "baseURL": "https://api.openai.com/v1",
                "apiKey": "test-key"
            ]
        )
        let request = try backend.makeChatRequest(
            endpoint: endpoint,
            instructions: "Reply concisely.",
            history: [
                WheelConversationTurn(role: .user, text: "List the attorneys.", priority: 950),
                WheelConversationTurn(role: .assistant, text: "Richard A. Brouillet; Camelia Mahmoudi.", priority: 800),
            ],
            prompt: "Put that in a table.",
            options: WheelTextGenerationOptions(deterministic: true),
            stream: false
        )

        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(json["messages"] as? [[String: Any]])

        #expect(messages.count == 4)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "Reply concisely.")
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == "List the attorneys.")
        #expect(messages[2]["role"] as? String == "assistant")
        #expect(messages[2]["content"] as? String == "Richard A. Brouillet; Camelia Mahmoudi.")
        #expect(messages[3]["role"] as? String == "user")
        #expect(messages[3]["content"] as? String == "Put that in a table.")
    }

    @Test("Apple backend folds prior transcript into instructions")
    func appleBackendFoldsPriorTranscriptIntoInstructions() {
        let backend = WheelAppleBackend()
        let instructions = backend.buildInstructions(
            instructions: "Reply concisely.",
            history: [
                WheelConversationTurn(role: .user, text: "List the attorneys.", priority: 950),
                WheelConversationTurn(role: .assistant, text: "Richard A. Brouillet; Camelia Mahmoudi.", priority: 800),
            ]
        )

        #expect(instructions?.contains("Reply concisely.") == true)
        #expect(instructions?.contains("Prior conversation:") == true)
        #expect(instructions?.contains("User: List the attorneys.") == true)
        #expect(instructions?.contains("Assistant: Richard A. Brouillet; Camelia Mahmoudi.") == true)
    }

    private func makeService(
        backendState: RecordingBackendState = RecordingBackendState(
            responses: [#"{"answer":"Rendered table"}"#]
        )
    ) -> WheelModelContextService {
        let runtime = ThreadRuntimeConfiguration(
            inference: ModelEndpoint(
                backendID: "fake-wheel-chat",
                modelID: "test-model"
            )
        )
        return WheelModelContextService(
            storageRootURL: URL(fileURLWithPath: "/tmp/WheelModelContextServiceTests", isDirectory: true),
            modelConfigurationProvider: FixedWheelTestModelConfigurationProvider(
                resolved: WheelResolvedModelConfiguration(
                    profile: WheelModelProfile(
                        providerID: .openAI,
                        modelID: "test-model",
                        baseURL: nil,
                        contextWindowOverride: nil,
                        appleGuardrails: .default
                    ),
                    threadRuntimeConfiguration: runtime
                )
            ),
            backends: [
                "fake-wheel-chat": RecordingBackend(
                    backendID: "fake-wheel-chat",
                    state: backendState
                )
            ]
        )
    }
}

private struct FixedWheelTestModelConfigurationProvider: WheelModelConfigurationProviding {
    let resolved: WheelResolvedModelConfiguration

    func currentProfile() -> WheelModelProfile {
        resolved.profile
    }

    func resolvedConfiguration() -> WheelResolvedModelConfiguration {
        resolved
    }
}

private actor RecordingBackendState {
    struct Call: Sendable, Equatable {
        let instructions: String?
        let history: [WheelConversationTurn]
        let prompt: String
    }

    private var callsStorage: [Call] = []
    private var responses: [String]

    init(responses: [String]) {
        self.responses = responses
    }

    func nextResponse(
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String
    ) -> String {
        callsStorage.append(
            Call(
                instructions: instructions,
                history: history,
                prompt: prompt
            )
        )
        if responses.isEmpty {
            return #"{"answer":"Rendered table"}"#
        }
        return responses.removeFirst()
    }

    func calls() -> [Call] {
        callsStorage
    }
}

private struct RecordingBackend: WheelLLMBackend {
    let backendID: String
    let state: RecordingBackendState

    func availability(for endpoint: ModelEndpoint) async -> RuntimeAvailability {
        _ = endpoint
        return RuntimeAvailability(
            status: .available,
            capabilities: RuntimeCapabilities(
                supportsTextGeneration: true,
                supportsTextStreaming: true,
                supportsStructuredOutput: true,
                supportsExactTokenEstimation: false,
                supportsLocaleHints: false
            )
        )
    }

    func generateText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) async throws -> String {
        _ = endpoint
        _ = options
        return await state.nextResponse(
            instructions: instructions,
            history: history,
            prompt: prompt
        )
    }

    func streamText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) -> AsyncThrowingStream<WheelTextStreamChunk, Error> {
        _ = endpoint
        _ = options
        return AsyncThrowingStream { continuation in
            Task {
                let response = await state.nextResponse(
                    instructions: instructions,
                    history: history,
                    prompt: prompt
                )
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }
    }
}
