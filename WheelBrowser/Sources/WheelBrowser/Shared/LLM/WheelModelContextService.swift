import Foundation

typealias WheelNormalizedTurn = WheelConversationTurn

struct WheelTurnMetadata: Sendable, Equatable {
    let truncation: WheelTranscriptTruncation?

    init(truncation: WheelTranscriptTruncation? = nil) {
        self.truncation = truncation
    }

    init(
        compaction: Never? = nil,
        bridge: Never? = nil,
        truncation: WheelTranscriptTruncation? = nil
    ) {
        _ = compaction
        _ = bridge
        self.truncation = truncation
    }
}

struct WheelGeneratedReply<Value: Sendable>: Sendable {
    let value: Value
    let transcriptText: String
    let metadata: WheelTurnMetadata
    let modelDisplayName: String
}

enum WheelChatStreamEvent: Sendable {
    case thinking(trace: String)
    case partial(answer: String)
    case completed(WheelGeneratedReply<GeneratedChatAssistantResponse>)
}

enum WheelPlainChatStreamEvent: Sendable {
    case thinking(trace: String)
    case partial(answer: String)
    case completed(WheelGeneratedReply<String>)
}

enum WheelAgentDecisionStreamEvent: Sendable {
    case partialThought(String)
    case completed(WheelGeneratedReply<GeneratedAgentDecision>)
}

enum WheelSummaryStreamEvent: Sendable {
    case partial(summary: String)
    case completed(WheelGeneratedReply<GeneratedSummaryResponse>)
}

protocol WheelModelContextServing: Sendable {
    func availabilityStatus() async -> WheelModelAvailability
    func streamPlainChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error>
    func streamChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error>
    func generateSettingsRouteDecision(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision>
    func generateSettingsPlan(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan>
    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String
    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent>
    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error>
    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation>
    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws
    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse>
    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error>
    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan>
    func sessionExists(sessionID: String) async -> Bool
    func resetSession(sessionID: String) async throws
}

actor WheelModelContextService: WheelModelContextServing {
    static let shared = WheelModelContextService()
    static let settingsAssistantApple = WheelModelContextService(
        storageRootURL: FileManager.appSupportDirectory.appendingPathComponent(
            "WheelSettingsAssistantApple",
            isDirectory: true
        ),
        modelConfigurationProvider: WheelFixedModelConfigurationProvider.settingsAssistantApple
    )

    private struct PreparedRequest: Sendable {
        let runtime: ThreadRuntimeConfiguration
        let instructions: String?
        let history: [WheelConversationTurn]
        let prompt: String
        let truncation: WheelTranscriptTruncation?
        let budget: BudgetReport
    }

    private struct AgentSessionState: Sendable {
        var runtime: ThreadRuntimeConfiguration
        var instructions: String
        var history: [WheelConversationTurn]
    }

    nonisolated let storageRootURL: URL

    private let modelConfigurationProvider: any WheelModelConfigurationProviding
    private let budgetPolicy: BudgetPolicy
    private let backends: [String: any WheelLLMBackend]

    private var agentSessions: [String: AgentSessionState] = [:]

    init(
        storageRootURL: URL = FileManager.appSupportDirectory.appendingPathComponent(
            "WheelLLM",
            isDirectory: true
        ),
        modelConfigurationProvider: any WheelModelConfigurationProviding = WheelModelConfigurationProvider.shared,
        backends: [String: any WheelLLMBackend] = WheelModelContextService.defaultBackends()
    ) {
        self.storageRootURL = storageRootURL
        self.modelConfigurationProvider = modelConfigurationProvider
        self.budgetPolicy = modelConfigurationProvider.currentProfile().providerID.defaultBudgetPolicy
        self.backends = backends
    }

    func availabilityStatus() async -> WheelModelAvailability {
        let resolvedConfiguration = modelConfigurationProvider.resolvedConfiguration()
        guard let backend = backends[resolvedConfiguration.threadRuntimeConfiguration.inference.backendID] else {
            return .unavailable(
                profile: resolvedConfiguration.profile,
                reason: "No backend configured for \(resolvedConfiguration.threadRuntimeConfiguration.inference.backendID)"
            )
        }

        return WheelModelAvailability(
            profile: resolvedConfiguration.profile,
            runtimeAvailability: await backend.availability(for: resolvedConfiguration.threadRuntimeConfiguration.inference)
        )
    }

    func streamPlainChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await makePlainTextStream(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: prompt,
            modelDisplayName: modelDisplayName
        )
    }

    func streamChatResponse(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        let configuredSpec = compatibleSpec(
            GeneratedChatAssistantResponse.spec,
            for: runtime.inference
        )
        return try await makeStructuredStream(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: prompt,
            spec: configuredSpec,
            partialFieldName: "answer",
            transcriptRenderer: { $0.answer },
            modelDisplayName: modelDisplayName,
            mapThinking: { .thinking(trace: $0) },
            mapPartial: { .partial(answer: $0) },
            mapCompleted: { .completed($0) }
        )
    }

    func generateSettingsRouteDecision(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await generateStructuredTextReply(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: prompt,
            spec: compatibleSpec(GeneratedSettingsRouteDecision.spec, for: runtime.inference),
            transcriptRenderer: { "Settings route: \($0.normalizedRoute.rawValue)" },
            modelDisplayName: modelDisplayName
        )
    }

    func generateSettingsPlan(
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await generateStructuredTextReply(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: prompt,
            spec: compatibleSpec(GeneratedSettingsPlan.spec, for: runtime.inference),
            transcriptRenderer: { $0.reply },
            modelDisplayName: modelDisplayName
        )
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        let sessionID = Self.agentSessionID(tabId: tabId, runId: runId)
        agentSessions[sessionID] = AgentSessionState(
            runtime: modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration,
            instructions: instructions,
            history: []
        )
        return sessionID
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        _ = requestID
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await generateStructuredTextReply(
            runtime: runtime,
            instructions: instructions,
            history: [],
            prompt: task,
            spec: compatibleSpec(GeneratedAgentTaskIntent.spec, for: runtime.inference),
            transcriptRenderer: { _ in "Agent task intent extracted" },
            modelDisplayName: modelDisplayName
        )
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        guard let session = agentSessions[sessionID] else {
            throw ContextManagerError.threadNotFound(sessionID)
        }
        let modelDisplayName = Self.displayName(for: session.runtime.inference)
        let configuredSpec = compatibleSpec(
            GeneratedAgentDecision.spec,
            for: session.runtime.inference
        )
        return try await makeStructuredStream(
            runtime: session.runtime,
            instructions: session.instructions,
            history: session.history,
            prompt: prompt,
            spec: configuredSpec,
            partialFieldName: "thought",
            transcriptRenderer: { $0.transcriptSummary },
            modelDisplayName: modelDisplayName,
            mapPartial: { .partialThought($0) },
            mapCompleted: { .completed($0) },
            onCompletedReply: { [weak self] transcriptText in
                await self?.appendAgentInteraction(
                    sessionID: sessionID,
                    prompt: prompt,
                    transcriptText: transcriptText
                )
            }
        )
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        _ = requestID
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await generateStructuredTextReply(
            runtime: runtime,
            instructions: instructions,
            history: [],
            prompt: prompt,
            spec: compatibleSpec(GeneratedAgentCompletionEvaluation.spec, for: runtime.inference),
            transcriptRenderer: { response in
                response.isComplete ? "Completion accepted" : "Completion rejected"
            },
            modelDisplayName: modelDisplayName
        )
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        guard var session = agentSessions[sessionID] else {
            throw ContextManagerError.threadNotFound(sessionID)
        }

        let normalizedTags = ["tool"] + tags.filter { $0 != "tool" }
        session.history.append(
            WheelConversationTurn(
                role: .system,
                text: text,
                priority: 700,
                tags: normalizedTags
            )
        )
        agentSessions[sessionID] = session
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        _ = requestID
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await generateStructuredTextReply(
            runtime: runtime,
            instructions: instructions,
            history: [],
            prompt: prompt,
            spec: compatibleSpec(GeneratedSummaryResponse.spec, for: runtime.inference),
            transcriptRenderer: { $0.summary },
            modelDisplayName: modelDisplayName
        )
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        _ = requestID
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await makeStructuredStream(
            runtime: runtime,
            instructions: instructions,
            history: [],
            prompt: prompt,
            spec: compatibleSpec(GeneratedSummaryResponse.spec, for: runtime.inference),
            partialFieldName: "summary",
            transcriptRenderer: { $0.summary },
            modelDisplayName: modelDisplayName,
            mapPartial: { .partial(summary: $0) },
            mapCompleted: { .completed($0) }
        )
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        _ = requestID
        let runtime = modelConfigurationProvider.resolvedConfiguration().threadRuntimeConfiguration
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        return try await generateStructuredTextReply(
            runtime: runtime,
            instructions: instructions,
            history: [],
            prompt: prompt,
            spec: compatibleSpec(GeneratedWidgetPlan.spec, for: runtime.inference),
            transcriptRenderer: transcriptRenderer,
            modelDisplayName: modelDisplayName
        )
    }

    func sessionExists(sessionID: String) async -> Bool {
        agentSessions[sessionID] != nil
    }

    func resetSession(sessionID: String) async throws {
        agentSessions.removeValue(forKey: sessionID)
    }

    private func appendAgentInteraction(
        sessionID: String,
        prompt: String,
        transcriptText: String
    ) {
        guard var session = agentSessions[sessionID] else {
            return
        }
        session.history.append(
            WheelConversationTurn(
                role: .user,
                text: prompt,
                priority: 950
            )
        )
        session.history.append(
            WheelConversationTurn(
                role: .assistant,
                text: transcriptText,
                priority: 800
            )
        )
        agentSessions[sessionID] = session
    }

    private func makeStructuredStream<Value: Sendable, Event>(
        runtime: ThreadRuntimeConfiguration,
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String,
        spec: StructuredOutputSpec<Value>,
        partialFieldName: String,
        transcriptRenderer: @escaping @Sendable (Value) -> String,
        modelDisplayName: String,
        mapThinking: (@Sendable (String) -> Event)? = nil,
        mapPartial: @escaping @Sendable (String) -> Event,
        mapCompleted: @escaping @Sendable (WheelGeneratedReply<Value>) -> Event,
        onCompletedReply: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AsyncThrowingStream<Event, Error> {
        let streamPrompt = WheelStructuredStreamingPrompt.build(
            basePrompt: prompt,
            spec: spec
        )
        let prepared = try prepareRequest(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: streamPrompt
        )
        let backend = try resolveBackend(for: runtime.inference)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = backend.streamText(
                        endpoint: prepared.runtime.inference,
                        instructions: prepared.instructions,
                        history: prepared.history,
                        prompt: prepared.prompt,
                        options: WheelTextGenerationOptions(
                            maximumResponseTokens: self.budgetPolicy.reservedOutputTokens
                        )
                    )
                    var aggregate = ""
                    var finalText = ""
                    var lastPartial = ""
                    var reasoningTrace = ""

                    for try await event in stream {
                        switch event {
                        case .reasoning(let partial):
                            guard partial.isEmpty == false else {
                                continue
                            }
                            reasoningTrace += partial
                            if let mapThinking {
                                continuation.yield(mapThinking(reasoningTrace))
                            }
                        case .partial(let partial):
                            aggregate = WheelStructuredStreamAccumulator.merge(
                                existing: aggregate,
                                incoming: partial
                            )

                            guard let extracted = WheelStructuredJSONExtractor.topLevelStringValue(
                                named: partialFieldName,
                                in: aggregate
                            ) else {
                                continue
                            }

                            let normalized = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard normalized.isEmpty == false, normalized != lastPartial else {
                                continue
                            }

                            lastPartial = normalized
                            continuation.yield(mapPartial(normalized))

                        case .completed(let result):
                            finalText = result
                            aggregate = result
                        }
                    }

                    let candidateText = finalText.isEmpty ? aggregate : finalText
                    guard candidateText.isEmpty == false else {
                        throw RuntimeError.generationFailed("Streaming finished without completion")
                    }

                    let reply = try await self.finalizeStructuredText(
                        prepared: prepared,
                        originalPrompt: prompt,
                        responseText: candidateText,
                        spec: spec,
                        transcriptRenderer: transcriptRenderer,
                        modelDisplayName: modelDisplayName
                    )
                    if let onCompletedReply {
                        await onCompletedReply(reply.transcriptText)
                    }
                    continuation.yield(mapCompleted(reply))
                    continuation.finish()
                } catch let error as RuntimeError where Self.isUnsupportedTextStreaming(error) {
                    do {
                        let reply = try await self.generateStructuredTextReply(
                            runtime: runtime,
                            instructions: instructions,
                            history: history,
                            prompt: prompt,
                            spec: spec,
                            transcriptRenderer: transcriptRenderer,
                            modelDisplayName: modelDisplayName
                        )
                        if let onCompletedReply {
                            await onCompletedReply(reply.transcriptText)
                        }
                        continuation.yield(mapCompleted(reply))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makePlainTextStream(
        runtime: ThreadRuntimeConfiguration,
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String,
        modelDisplayName: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        let prepared = try prepareRequest(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: prompt
        )
        let backend = try resolveBackend(for: runtime.inference)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = backend.streamText(
                        endpoint: prepared.runtime.inference,
                        instructions: prepared.instructions,
                        history: prepared.history,
                        prompt: prepared.prompt,
                        options: WheelTextGenerationOptions(
                            maximumResponseTokens: self.budgetPolicy.reservedOutputTokens
                        )
                    )
                    var aggregate = ""
                    var completionText = ""
                    var reasoningTrace = ""

                    for try await event in stream {
                        switch event {
                        case .reasoning(let partial):
                            guard partial.isEmpty == false else {
                                continue
                            }
                            reasoningTrace += partial
                            continuation.yield(.thinking(trace: reasoningTrace))
                        case .partial(let partial):
                            aggregate = WheelStructuredStreamAccumulator.merge(
                                existing: aggregate,
                                incoming: partial
                            )
                            continuation.yield(.partial(answer: aggregate))
                        case .completed(let result):
                            completionText = result
                        }
                    }

                    let finalText = completionText.isEmpty ? aggregate : completionText
                    guard finalText.isEmpty == false else {
                        throw RuntimeError.generationFailed("Streaming finished without completion")
                    }
                    continuation.yield(
                        .completed(
                            WheelGeneratedReply(
                                value: finalText,
                                transcriptText: finalText,
                                metadata: WheelTurnMetadata(truncation: prepared.truncation),
                                modelDisplayName: modelDisplayName
                            )
                        )
                    )
                    continuation.finish()
                } catch let error as RuntimeError where Self.isUnsupportedTextStreaming(error) {
                    do {
                        let reply = try await self.generatePlainTextReply(
                            runtime: runtime,
                            instructions: instructions,
                            history: history,
                            prompt: prompt,
                            modelDisplayName: modelDisplayName
                        )
                        continuation.yield(.completed(reply))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func generatePlainTextReply(
        runtime: ThreadRuntimeConfiguration,
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String,
        modelDisplayName: String
    ) async throws -> WheelGeneratedReply<String> {
        let prepared = try prepareRequest(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: prompt
        )
        let backend = try resolveBackend(for: runtime.inference)
        let response = try await backend.generateText(
            endpoint: prepared.runtime.inference,
            instructions: prepared.instructions,
            history: prepared.history,
            prompt: prepared.prompt,
            options: WheelTextGenerationOptions(
                maximumResponseTokens: budgetPolicy.reservedOutputTokens
            )
        )
        return WheelGeneratedReply(
            value: response,
            transcriptText: response,
            metadata: WheelTurnMetadata(truncation: prepared.truncation),
            modelDisplayName: modelDisplayName
        )
    }

    private func generateStructuredTextReply<Value: Sendable>(
        runtime: ThreadRuntimeConfiguration,
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String,
        spec: StructuredOutputSpec<Value>,
        transcriptRenderer: (@Sendable (Value) -> String)? = nil,
        modelDisplayName: String
    ) async throws -> WheelGeneratedReply<Value> {
        let effectiveTranscriptRenderer = transcriptRenderer ?? spec.transcriptRenderer
        let textPrompt = WheelStructuredStreamingPrompt.build(
            basePrompt: prompt,
            spec: spec
        )
        let prepared = try prepareRequest(
            runtime: runtime,
            instructions: instructions,
            history: history,
            prompt: textPrompt
        )
        let backend = try resolveBackend(for: runtime.inference)
        let response = try await backend.generateText(
            endpoint: prepared.runtime.inference,
            instructions: prepared.instructions,
            history: prepared.history,
            prompt: prepared.prompt,
            options: WheelTextGenerationOptions(
                maximumResponseTokens: budgetPolicy.reservedOutputTokens,
                deterministic: true
            )
        )
        return try await finalizeStructuredText(
            prepared: prepared,
            originalPrompt: prompt,
            responseText: response,
            spec: spec,
            transcriptRenderer: effectiveTranscriptRenderer,
            modelDisplayName: modelDisplayName
        )
    }

    private func finalizeStructuredText<Value: Sendable>(
        prepared: PreparedRequest,
        originalPrompt: String,
        responseText: String,
        spec: StructuredOutputSpec<Value>,
        transcriptRenderer: @escaping @Sendable (Value) -> String,
        modelDisplayName: String
    ) async throws -> WheelGeneratedReply<Value> {
        if let decoded = try decodeStructuredValue(from: responseText, spec: spec) {
            let transcriptText = transcriptRenderer(decoded)
            return WheelGeneratedReply(
                value: decoded,
                transcriptText: transcriptText,
                metadata: WheelTurnMetadata(truncation: prepared.truncation),
                modelDisplayName: modelDisplayName
            )
        }

        let repaired = try await repairStructuredValue(
            prepared: prepared,
            originalPrompt: originalPrompt,
            invalidResponse: responseText,
            spec: spec
        )
        let transcriptText = transcriptRenderer(repaired)
        return WheelGeneratedReply(
            value: repaired,
            transcriptText: transcriptText,
            metadata: WheelTurnMetadata(truncation: prepared.truncation),
            modelDisplayName: modelDisplayName
        )
    }

    private func repairStructuredValue<Value: Sendable>(
        prepared: PreparedRequest,
        originalPrompt: String,
        invalidResponse: String,
        spec: StructuredOutputSpec<Value>
    ) async throws -> Value {
        let backend = try resolveBackend(for: prepared.runtime.inference)
        let repairPrompt = """
        The previous response did not decode as valid JSON for the requested schema.

        Original task:
        \(originalPrompt)

        Required schema:
        \(WheelOutputSchemaPromptRenderer.render(schema: spec.schema))

        Invalid response:
        \(invalidResponse)

        Rewrite the answer as exactly one valid JSON object and nothing else.
        """
        let repairedText = try await backend.generateText(
            endpoint: prepared.runtime.inference,
            instructions: prepared.instructions,
            history: prepared.history,
            prompt: repairPrompt,
            options: WheelTextGenerationOptions(
                maximumResponseTokens: budgetPolicy.reservedOutputTokens,
                deterministic: true
            )
        )
        if let decoded = try decodeStructuredValue(from: repairedText, spec: spec) {
            return decoded
        }
        throw RuntimeError.generationFailed("The model response did not match the expected JSON schema")
    }

    private func decodeStructuredValue<Value: Sendable>(
        from streamedText: String,
        spec: StructuredOutputSpec<Value>
    ) throws -> Value? {
        for jsonText in WheelStructuredJSONExtractor.candidateJSONObjectStrings(in: streamedText) {
            guard let data = jsonText.data(using: .utf8) else {
                continue
            }
            if let decoded = try? spec.decode(data) {
                return decoded
            }
        }
        return nil
    }

    private func prepareRequest(
        runtime: ThreadRuntimeConfiguration,
        instructions: String,
        history: [WheelConversationTurn],
        prompt: String
    ) throws -> PreparedRequest {
        let endpoint = runtime.inference
        let contextWindowTokens = endpoint.contextWindowOverride ?? budgetPolicy.defaultContextWindowTokens
        let inputBudget = max(1, contextWindowTokens - budgetPolicy.reservedOutputTokens)
        let normalizedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let fixedTokens = roughTokenCount(normalizedInstructions ?? "") + roughTokenCount(prompt)
        guard fixedTokens < inputBudget else {
            throw RuntimeError.contextOverflow("The request exceeds the available context window")
        }

        var retained: [WheelConversationTurn] = []
        var estimatedInputTokens = fixedTokens

        for turn in history.reversed() {
            let turnTokens = roughTokenCount(turn.text) + 6
            guard estimatedInputTokens + turnTokens <= inputBudget else {
                continue
            }
            retained.append(turn)
            estimatedInputTokens += turnTokens
        }

        retained.reverse()
        let droppedTurnCount = max(0, history.count - retained.count)
        let truncation = droppedTurnCount > 0
            ? WheelTranscriptTruncation(
                droppedTurnCount: droppedTurnCount,
                retainedTurnCount: retained.count,
                estimatedInputTokens: estimatedInputTokens,
                contextWindowTokens: contextWindowTokens
            )
            : nil

        return PreparedRequest(
            runtime: runtime,
            instructions: normalizedInstructions,
            history: retained,
            prompt: prompt,
            truncation: truncation,
            budget: BudgetReport(
                contextWindowTokens: contextWindowTokens,
                estimatedInputTokens: estimatedInputTokens,
                reservedOutputTokens: budgetPolicy.reservedOutputTokens,
                projectedTotalTokens: estimatedInputTokens + budgetPolicy.reservedOutputTokens
            )
        )
    }

    private func roughTokenCount(_ text: String) -> Int {
        guard text.isEmpty == false else {
            return 0
        }
        let bytes = text.lengthOfBytes(using: .utf8)
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let base = max(
            Int(ceil(Double(bytes) / 4.0)),
            Int(ceil(Double(words) * 1.35))
        )
        return Int(ceil(Double(base + 6) * budgetPolicy.heuristicSafetyMultiplier))
    }

    private func compatibleSpec<Value: Sendable>(
        _ spec: StructuredOutputSpec<Value>,
        for endpoint: ModelEndpoint
    ) -> StructuredOutputSpec<Value> {
        guard endpoint.backendID == WheelModelProviderID.apple.rawValue else {
            return spec
        }

        let schema = WheelOutputSchema.removingStringLengthConstraints(from: spec.schema)
        return StructuredOutputSpec(
            schema: schema,
            decode: spec.decode,
            transcriptRenderer: spec.transcriptRenderer
        )
    }

    private func resolveBackend(for endpoint: ModelEndpoint) throws -> any WheelLLMBackend {
        guard let backend = backends[endpoint.backendID] else {
            throw RuntimeError.unavailable("No backend configured for \(endpoint.backendID)")
        }
        return backend
    }

    private static func defaultBackends() -> [String: any WheelLLMBackend] {
        [
            WheelModelProviderID.apple.rawValue: WheelAppleBackend(),
            WheelModelProviderID.openAI.rawValue: WheelOpenAICompatibleBackend(
                backendID: WheelModelProviderID.openAI.rawValue,
                kind: .openAI
            ),
            WheelModelProviderID.vllm.rawValue: WheelOpenAICompatibleBackend(
                backendID: WheelModelProviderID.vllm.rawValue,
                kind: .vllm
            )
        ]
    }

    nonisolated static func usesStreamingTextCompatibility(
        for providerID: WheelModelProviderID
    ) -> Bool {
        switch providerID {
        case .apple, .openAI, .vllm:
            return true
        }
    }

    nonisolated static func isUnsupportedTextStreaming(_ error: RuntimeError) -> Bool {
        if case .unsupportedCapability = error {
            return true
        }
        return false
    }

    nonisolated static func displayName(for endpoint: ModelEndpoint) -> String {
        let providerID = WheelModelProviderID(rawValue: endpoint.backendID)
        let providerName = providerID?.displayName ?? endpoint.backendID
        return "\(providerName) / \(endpoint.modelID)"
    }

    nonisolated static func chatSessionID(for conversationId: UUID) -> String {
        "chat:\(conversationId.uuidString.lowercased())"
    }

    nonisolated static func agentSessionID(tabId: UUID, runId: UUID) -> String {
        "agent:\(tabId.uuidString.lowercased()):\(runId.uuidString.lowercased())"
    }

    nonisolated static func agentIntentSessionID(for requestID: UUID) -> String {
        "agent-intent:\(requestID.uuidString.lowercased())"
    }

    nonisolated static func agentCompletionSessionID(for requestID: UUID) -> String {
        "agent-completion:\(requestID.uuidString.lowercased())"
    }

    nonisolated static func summarySessionID(for requestID: UUID) -> String {
        "summary:\(requestID.uuidString.lowercased())"
    }

    nonisolated static func widgetSessionID(for requestID: UUID) -> String {
        "widget:\(requestID.uuidString.lowercased())"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
