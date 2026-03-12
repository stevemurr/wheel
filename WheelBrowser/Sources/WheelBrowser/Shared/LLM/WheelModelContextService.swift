import Foundation
import LanguageModelApple
import LanguageModelContextManagement
import LanguageModelOpenAI
import LanguageModelStructuredOutput
import LanguageModelVLLM

typealias WheelNormalizedTurn = NormalizedTurn
typealias WheelDurableMemoryRecord = DurableMemoryRecord

struct WheelTurnMetadata: Sendable {
    let compaction: CompactionReport?
    let bridge: BridgeReport?
}

struct WheelGeneratedReply<Value: Sendable>: Sendable {
    let value: Value
    let transcriptText: String
    let metadata: WheelTurnMetadata
    let modelDisplayName: String
}

enum WheelChatStreamEvent: Sendable {
    case partial(answer: String)
    case completed(WheelGeneratedReply<GeneratedChatAssistantResponse>)
}

enum WheelPlainChatStreamEvent: Sendable {
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
    func openChatSession(conversationId: UUID, instructions: String) async throws
    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [WheelNormalizedTurn],
        durableMemory: [WheelDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws
    func streamPlainChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error>
    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error>
    func generateSettingsRouteDecision(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision>
    func generateSettingsPlan(
        conversationId: UUID,
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
            "LanguageModelKitSettingsAssistantApple",
            isDirectory: true
        ),
        modelConfigurationProvider: WheelFixedModelConfigurationProvider.settingsAssistantApple
    )

    private enum StructuredGenerationStrategy {
        case streamingTextCompatibility
        case oneShotTextCompatibility
    }

    private enum PlainTextGenerationStrategy {
        case streaming
        case oneShot
    }

    nonisolated let storageRootURL: URL

    private let contextManager: ContextManager
    private let runtimeRegistry: RuntimeRegistry
    private let threadStore: any ThreadStore
    private let modelConfigurationProvider: any WheelModelConfigurationProviding
    private let budgetPolicy: BudgetPolicy

    private var didBootstrapRuntime = false
    private var liveSessions: [String: ContextSession] = [:]
    private var liveSessionRuntimes: [String: ThreadRuntimeConfiguration] = [:]

    init(
        storageRootURL: URL = FileManager.appSupportDirectory.appendingPathComponent(
            "LanguageModelKit",
            isDirectory: true
        ),
        configuration: ContextManagerConfiguration? = nil,
        modelConfigurationProvider: any WheelModelConfigurationProviding = WheelModelConfigurationProvider.shared
    ) {
        self.storageRootURL = storageRootURL
        self.modelConfigurationProvider = modelConfigurationProvider

        let managedConfiguration: ContextManagerConfiguration
        if let configuration {
            managedConfiguration = configuration
        } else {
            let runtimeRegistry = RuntimeRegistry()
            let persistence = PersistencePolicy(
                threads: FileThreadStore(
                    directoryURL: storageRootURL.appendingPathComponent("threads", isDirectory: true)
                ),
                memories: FileMemoryStore(
                    directoryURL: storageRootURL.appendingPathComponent("memories", isDirectory: true)
                ),
                blobs: FileBlobStore(
                    directoryURL: storageRootURL.appendingPathComponent("blobs", isDirectory: true)
                ),
                retriever: nil
            )

            managedConfiguration = ContextManagerConfiguration(
                runtimeRegistry: runtimeRegistry,
                structuredBackends: Self.defaultStructuredBackends(),
                budget: BudgetPolicy(defaultContextWindowTokens: 4096),
                persistence: persistence
            )
        }

        self.runtimeRegistry = managedConfiguration.runtimeRegistry
        self.threadStore = managedConfiguration.persistence.threads
        self.contextManager = ContextManager(configuration: managedConfiguration)
        self.budgetPolicy = managedConfiguration.budget
    }

    func availabilityStatus() async -> WheelModelAvailability {
        await ensureBootstrappedRuntime()

        let resolvedConfiguration = modelConfigurationProvider.resolvedConfiguration()
        let availability = await contextManager.availability(
            for: resolvedConfiguration.threadRuntimeConfiguration.inference
        )
        return WheelModelAvailability(
            profile: resolvedConfiguration.profile,
            runtimeAvailability: availability
        )
    }

    func openChatSession(conversationId: UUID, instructions: String) async throws {
        let sessionID = Self.chatSessionID(for: conversationId)
        Log.Services.debug("openChatSession: id=\(sessionID), model=\(modelConfigurationProvider.currentProfile().displayName)")
        _ = try await openSession(
            id: sessionID,
            instructions: instructions
        )
    }

    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [WheelNormalizedTurn],
        durableMemory: [WheelDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {
        let sessionID = Self.chatSessionID(for: conversationId)
        Log.Services.debug("importChatSession: id=\(sessionID), turns=\(turns.count), durableMemory=\(durableMemory.count), replaceExisting=\(replaceExisting)")
        let session = try await openSession(
            id: sessionID,
            instructions: instructions
        )
        try await session.maintenance.importHistory(
            turns,
            durableMemory: durableMemory,
            replaceExisting: replaceExisting
        )
    }

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        let sessionID = Self.chatSessionID(for: conversationId)
        Log.Services.debug("streamChatResponse: resolving session id=\(sessionID)")
        let session = try await resolveSession(id: sessionID)
        let modelDisplayName = await modelDisplayName(for: sessionID)
        let configuredSpec = await compatibleSpec(GeneratedChatAssistantResponse.spec, for: sessionID)
        let strategy = await structuredGenerationStrategy(for: sessionID)

        switch strategy {
        case .streamingTextCompatibility:
            return makeStructuredStream(
                session: session,
                prompt: prompt,
                spec: configuredSpec,
                partialFieldName: "answer",
                transcriptRenderer: { $0.answer },
                modelDisplayName: modelDisplayName,
                mapPartial: { .partial(answer: $0) },
                mapCompleted: { .completed($0) }
            )
        case .oneShotTextCompatibility:
            Log.Services.info("streamChatResponse: using one-shot text compatibility mode for id=\(sessionID)")
            return makeStructuredOneShotTextStream(
                session: session,
                prompt: prompt,
                spec: configuredSpec,
                transcriptRenderer: { $0.answer },
                modelDisplayName: modelDisplayName,
                mapCompleted: { .completed($0) }
            )
        }
    }

    func streamPlainChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        let sessionID = Self.chatSessionID(for: conversationId)
        Log.Services.debug("streamPlainChatResponse: resolving session id=\(sessionID)")
        let session = try await resolveSession(id: sessionID)
        let modelDisplayName = await modelDisplayName(for: sessionID)
        let strategy = await plainTextGenerationStrategy(for: sessionID)
        await logPlainTextRequestTrace(
            route: "streamPlainChatResponse",
            sessionID: sessionID,
            strategy: strategy,
            prompt: prompt
        )

        switch strategy {
        case .streaming:
            return makePlainTextStream(
                session: session,
                prompt: prompt,
                modelDisplayName: modelDisplayName
            )
        case .oneShot:
            Log.Services.info("streamPlainChatResponse: using one-shot text mode for id=\(sessionID)")
            return makePlainTextOneShotStream(
                session: session,
                prompt: prompt,
                modelDisplayName: modelDisplayName
            )
        }
    }

    func generateSettingsRouteDecision(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsRouteDecision> {
        let sessionID = Self.chatSessionID(for: conversationId)
        let session = try await resolveSession(id: sessionID)
        let modelDisplayName = await modelDisplayName(for: sessionID)
        let response = try await session.reply(
            to: prompt,
            spec: await compatibleSpec(GeneratedSettingsRouteDecision.spec, for: sessionID)
        )
        return mapReply(
            response,
            transcriptRenderer: { "Settings route: \($0.normalizedRoute.rawValue)" },
            modelDisplayName: modelDisplayName
        )
    }

    func generateSettingsPlan(
        conversationId: UUID,
        prompt: String
    ) async throws -> WheelGeneratedReply<GeneratedSettingsPlan> {
        let sessionID = Self.chatSessionID(for: conversationId)
        let session = try await resolveSession(id: sessionID)
        let modelDisplayName = await modelDisplayName(for: sessionID)
        let response = try await session.reply(
            to: prompt,
            spec: await compatibleSpec(GeneratedSettingsPlan.spec, for: sessionID)
        )
        return mapReply(
            response,
            transcriptRenderer: { $0.reply },
            modelDisplayName: modelDisplayName
        )
    }

    func openAgentSession(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        let sessionID = Self.agentSessionID(tabId: tabId, runId: runId)
        _ = try await openSession(id: sessionID, instructions: instructions)
        return sessionID
    }

    func generateAgentTaskIntent(
        requestID: UUID,
        task: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentTaskIntent> {
        let sessionID = Self.agentIntentSessionID(for: requestID)
        let session = try await openSession(
            id: sessionID,
            instructions: instructions
        )
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        let response = try await session.reply(
            to: task,
            spec: await compatibleSpec(GeneratedAgentTaskIntent.spec, for: sessionID)
        )
        return mapReply(
            response,
            transcriptRenderer: { _ in "Agent task intent extracted" },
            modelDisplayName: modelDisplayName
        )
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        let session = try await resolveSession(id: sessionID)
        let modelDisplayName = await modelDisplayName(for: sessionID)
        let configuredSpec = await compatibleSpec(GeneratedAgentDecision.spec, for: sessionID)
        let strategy = await structuredGenerationStrategy(for: sessionID)

        switch strategy {
        case .streamingTextCompatibility:
            return makeStructuredStream(
                session: session,
                prompt: prompt,
                spec: configuredSpec,
                partialFieldName: "thought",
                transcriptRenderer: { $0.transcriptSummary },
                modelDisplayName: modelDisplayName,
                mapPartial: { .partialThought($0) },
                mapCompleted: { .completed($0) }
            )
        case .oneShotTextCompatibility:
            Log.Services.info("streamAgentDecision: using one-shot text compatibility mode for id=\(sessionID)")
            return makeStructuredOneShotTextStream(
                session: session,
                prompt: prompt,
                spec: configuredSpec,
                transcriptRenderer: { $0.transcriptSummary },
                modelDisplayName: modelDisplayName,
                mapCompleted: { .completed($0) }
            )
        }
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        let sessionID = Self.agentCompletionSessionID(for: requestID)
        let session = try await openSession(
            id: sessionID,
            instructions: instructions
        )
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        let response = try await session.reply(
            to: prompt,
            spec: await compatibleSpec(GeneratedAgentCompletionEvaluation.spec, for: sessionID)
        )
        return mapReply(
            response,
            transcriptRenderer: { response in
                response.isComplete ? "Completion accepted" : "Completion rejected"
            },
            modelDisplayName: modelDisplayName
        )
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        let session = try await resolveSession(id: sessionID)

        guard let diagnostics = await session.inspection.diagnostics() else {
            throw ContextManagerError.threadNotFound(sessionID)
        }

        let normalizedTags = ["tool"] + tags.filter { $0 != "tool" }
        let turn = WheelNormalizedTurn(
            role: .system,
            text: text,
            priority: 700,
            tags: normalizedTags,
            windowIndex: diagnostics.windowIndex
        )
        try await session.maintenance.appendTurns([turn])
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        let sessionID = Self.summarySessionID(for: requestID)
        let session = try await openSession(
            id: sessionID,
            instructions: instructions
        )
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        let response = try await session.reply(
            to: prompt,
            spec: await compatibleSpec(GeneratedSummaryResponse.spec, for: sessionID)
        )
        return mapReply(
            response,
            transcriptRenderer: { $0.summary },
            modelDisplayName: modelDisplayName
        )
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        let sessionID = Self.summarySessionID(for: requestID)
        let session = try await openSession(id: sessionID, instructions: instructions)
        let modelDisplayName = await modelDisplayName(for: sessionID)
        let configuredSpec = await compatibleSpec(GeneratedSummaryResponse.spec, for: sessionID)
        let strategy = await structuredGenerationStrategy(for: sessionID)

        switch strategy {
        case .streamingTextCompatibility:
            return makeStructuredStream(
                session: session,
                prompt: prompt,
                spec: configuredSpec,
                partialFieldName: "summary",
                transcriptRenderer: { $0.summary },
                modelDisplayName: modelDisplayName,
                mapPartial: { .partial(summary: $0) },
                mapCompleted: { .completed($0) }
            )
        case .oneShotTextCompatibility:
            Log.Services.info("streamSummary: using one-shot text compatibility mode for id=\(sessionID)")
            return makeStructuredOneShotTextStream(
                session: session,
                prompt: prompt,
                spec: configuredSpec,
                transcriptRenderer: { $0.summary },
                modelDisplayName: modelDisplayName,
                mapCompleted: { .completed($0) }
            )
        }
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)? = nil
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        let sessionID = Self.widgetSessionID(for: requestID)
        let session = try await openSession(
            id: sessionID,
            instructions: instructions
        )
        let modelDisplayName = modelConfigurationProvider.currentProfile().displayName
        let response = try await session.reply(
            to: prompt,
            spec: await compatibleSpec(GeneratedWidgetPlan.spec, for: sessionID)
        )
        return mapReply(
            response,
            transcriptRenderer: transcriptRenderer,
            modelDisplayName: modelDisplayName
        )
    }

    func sessionExists(sessionID: String) async -> Bool {
        if liveSessions[sessionID] != nil {
            Log.Services.debug("sessionExists: id=\(sessionID), exists=true (live)")
            return true
        }

        let exists = (try? await threadStore.load(threadID: sessionID)) != nil
        Log.Services.debug("sessionExists: id=\(sessionID), exists=\(exists)")
        return exists
    }

    func resetSession(sessionID: String) async throws {
        let session = try await resolveSession(id: sessionID)
        try await session.maintenance.reset()
        liveSessions.removeValue(forKey: sessionID)
        liveSessionRuntimes.removeValue(forKey: sessionID)
    }

    private func openSession(
        id: String,
        instructions: String
    ) async throws -> ContextSession {
        await ensureBootstrappedRuntime()

        let resolvedConfiguration = modelConfigurationProvider.resolvedConfiguration()
        Log.Services.debug("openSession: id=\(id), model=\(resolvedConfiguration.profile.displayName), storageRoot=\(storageRootURL.path)")
        let configuration = ThreadConfiguration(
            runtime: resolvedConfiguration.threadRuntimeConfiguration,
            instructions: instructions,
            locale: nil
        )
        let session = try await contextManager.session(id: id, configuration: configuration)
        liveSessions[id] = session
        liveSessionRuntimes[id] = resolvedConfiguration.threadRuntimeConfiguration
        return session
    }

    private func resolveSession(id: String) async throws -> ContextSession {
        await ensureBootstrappedRuntime()

        if let session = liveSessions[id] {
            Log.Services.debug("resolveSession: using live session for id=\(id)")
            return session
        }

        guard let state = try await threadStore.load(threadID: id) else {
            Log.Services.warning("resolveSession: missing persisted state for id=\(id), storageRoot=\(storageRootURL.path)")
            throw ContextManagerError.threadNotFound(id)
        }

        Log.Services.debug("resolveSession: loaded persisted state for id=\(id), turnCount=\(state.turns.count), updatedAt=\(state.updatedAt.ISO8601Format())")

        let configuration = ThreadConfiguration(
            runtime: state.runtime,
            instructions: state.instructions,
            locale: state.localeIdentifier.map(Locale.init(identifier:))
        )
        let session = try await contextManager.session(id: id, configuration: configuration)
        liveSessions[id] = session
        liveSessionRuntimes[id] = state.runtime
        return session
    }

    private func makeStructuredStream<Value: Sendable, Event>(
        session: ContextSession,
        prompt: String,
        spec: StructuredOutputSpec<Value>,
        partialFieldName: String,
        transcriptRenderer: @escaping @Sendable (Value) -> String,
        modelDisplayName: String,
        mapPartial: @escaping @Sendable (String) -> Event,
        mapCompleted: @escaping @Sendable (WheelGeneratedReply<Value>) -> Event
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let streamPrompt = WheelStructuredStreamingPrompt.build(
                        basePrompt: prompt,
                        spec: spec
                    )
                    let stream = session.stream(streamPrompt)
                    var aggregate = ""
                    var finalText = ""
                    var lastPartial = ""

                    for try await event in stream {
                        switch event {
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
                            finalText = result.text
                            aggregate = result.text
                        }
                    }

                    let candidateText = finalText.isEmpty ? aggregate : finalText
                    guard candidateText.isEmpty == false else {
                        throw RuntimeError.generationFailed("Streaming finished without completion")
                    }

                    let reply = try await self.finalizeStructuredStream(
                        session: session,
                        originalPrompt: prompt,
                        streamedText: candidateText,
                        spec: spec,
                        transcriptRenderer: transcriptRenderer,
                        modelDisplayName: modelDisplayName
                    )
                    continuation.yield(mapCompleted(reply))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeStructuredOneShotTextStream<Value: Sendable, Event>(
        session: ContextSession,
        prompt: String,
        spec: StructuredOutputSpec<Value>,
        transcriptRenderer: @escaping @Sendable (Value) -> String,
        modelDisplayName: String,
        mapCompleted: @escaping @Sendable (WheelGeneratedReply<Value>) -> Event
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let reply = try await self.generateStructuredFromTextReply(
                        session: session,
                        originalPrompt: prompt,
                        spec: spec,
                        transcriptRenderer: transcriptRenderer,
                        modelDisplayName: modelDisplayName
                    )
                    continuation.yield(mapCompleted(reply))
                    continuation.finish()
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
        session: ContextSession,
        prompt: String,
        modelDisplayName: String
    ) -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        AsyncThrowingStream { (continuation: AsyncThrowingStream<WheelPlainChatStreamEvent, Error>.Continuation) in
            let task = Task {
                do {
                    let stream = session.stream(prompt)
                    var aggregate = ""
                    var completionText = ""

                    for try await event in stream {
                        switch event {
                        case .partial(let partial):
                            aggregate = WheelStructuredStreamAccumulator.merge(
                                existing: aggregate,
                                incoming: partial
                            )
                            continuation.yield(WheelPlainChatStreamEvent.partial(answer: aggregate))

                        case .completed(let result):
                            completionText = result.text
                        }
                    }

                    let finalText = completionText.isEmpty ? aggregate : completionText
                    guard finalText.isEmpty == false else {
                        throw RuntimeError.generationFailed("Streaming finished without completion")
                    }
                    await self.logSessionDiagnostics(
                        route: "makePlainTextStream",
                        session: session,
                        responseLength: finalText.count
                    )
                    let finalMetadata = await self.metadata(for: session)

                    continuation.yield(
                        WheelPlainChatStreamEvent.completed(
                            WheelGeneratedReply(
                                value: finalText,
                                transcriptText: finalText,
                                metadata: finalMetadata,
                                modelDisplayName: modelDisplayName
                            )
                        )
                    )
                    continuation.finish()
                } catch let error as RuntimeError where Self.isUnsupportedTextStreaming(error) {
                    do {
                        let reply = try await self.generatePlainTextReply(
                            session: session,
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

    private func makePlainTextOneShotStream(
        session: ContextSession,
        prompt: String,
        modelDisplayName: String
    ) -> AsyncThrowingStream<WheelPlainChatStreamEvent, Error> {
        AsyncThrowingStream { (continuation: AsyncThrowingStream<WheelPlainChatStreamEvent, Error>.Continuation) in
            let task = Task {
                do {
                    let reply = try await self.generatePlainTextReply(
                        session: session,
                        prompt: prompt,
                        modelDisplayName: modelDisplayName
                    )
                    continuation.yield(WheelPlainChatStreamEvent.completed(reply))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func finalizeStructuredStream<Value: Sendable>(
        session: ContextSession,
        originalPrompt: String,
        streamedText: String,
        spec: StructuredOutputSpec<Value>,
        transcriptRenderer: @escaping @Sendable (Value) -> String,
        modelDisplayName: String
    ) async throws -> WheelGeneratedReply<Value> {
        if let decoded = try decodeStructuredValue(from: streamedText, spec: spec) {
            let transcriptText = transcriptRenderer(decoded)
            try await rewriteLastAssistantTurn(in: session, transcriptText: transcriptText)
            return WheelGeneratedReply(
                value: decoded,
                transcriptText: transcriptText,
                metadata: await metadata(for: session),
                modelDisplayName: modelDisplayName
            )
        }

        try await dropLastAssistantTurnIfNeeded(in: session)
        let response = try await session.reply(to: originalPrompt, spec: spec)
        return mapReply(
            response,
            transcriptRenderer: transcriptRenderer,
            modelDisplayName: modelDisplayName
        )
    }

    private func generateStructuredFromTextReply<Value: Sendable>(
        session: ContextSession,
        originalPrompt: String,
        spec: StructuredOutputSpec<Value>,
        transcriptRenderer: @escaping @Sendable (Value) -> String,
        modelDisplayName: String
    ) async throws -> WheelGeneratedReply<Value> {
        let textPrompt = WheelStructuredStreamingPrompt.build(
            basePrompt: originalPrompt,
            spec: spec
        )
        Log.Services.debug("generateStructuredFromTextReply: requesting one-shot text response for id=\(session.id)")
        let response = try await session.reply(to: textPrompt)
        let preview = response.text
            .replacingOccurrences(of: "\n", with: "\\n")
            .prefix(240)
        Log.Services.debug(
            "generateStructuredFromTextReply: received \(response.text.count) chars for id=\(session.id), preview=\(preview)"
        )

        if let decoded = try decodeStructuredValue(from: response.text, spec: spec) {
            let transcriptText = transcriptRenderer(decoded)
            try await rewriteLastAssistantTurn(in: session, transcriptText: transcriptText)
            return WheelGeneratedReply(
                value: decoded,
                transcriptText: transcriptText,
                metadata: WheelTurnMetadata(
                    compaction: response.metadata.compaction,
                    bridge: response.metadata.bridge
                ),
                modelDisplayName: modelDisplayName
            )
        }

        Log.Services.warning(
            "generateStructuredFromTextReply: text reply did not decode for id=\(session.id); retrying with structured fallback"
        )
        try await dropLastAssistantTurnIfNeeded(in: session)
        let structuredResponse: StructuredReply<Value>
        do {
            structuredResponse = try await session.reply(to: originalPrompt, spec: spec)
        } catch {
            Log.Services.error(
                "generateStructuredFromTextReply: structured fallback failed for id=\(session.id)",
                error: error
            )
            throw error
        }
        return mapReply(
            structuredResponse,
            transcriptRenderer: transcriptRenderer,
            modelDisplayName: modelDisplayName
        )
    }

    private func generatePlainTextReply(
        session: ContextSession,
        prompt: String,
        modelDisplayName: String
    ) async throws -> WheelGeneratedReply<String> {
        let response = try await session.reply(to: prompt)
        await logSessionDiagnostics(
            route: "generatePlainTextReply",
            session: session,
            responseLength: response.text.count
        )
        return WheelGeneratedReply(
            value: response.text,
            transcriptText: response.text,
            metadata: WheelTurnMetadata(
                compaction: response.metadata.compaction,
                bridge: response.metadata.bridge
            ),
            modelDisplayName: modelDisplayName
        )
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

    private func rewriteLastAssistantTurn(
        in session: ContextSession,
        transcriptText: String
    ) async throws {
        var history = try await session.inspection.history()
        guard let lastTurn = history.last, lastTurn.role == .assistant else {
            return
        }

        history[history.count - 1] = WheelNormalizedTurn(
            id: lastTurn.id,
            role: lastTurn.role,
            text: transcriptText,
            createdAt: lastTurn.createdAt,
            priority: lastTurn.priority,
            tags: lastTurn.tags,
            blobIDs: lastTurn.blobIDs,
            windowIndex: lastTurn.windowIndex,
            compacted: lastTurn.compacted
        )

        let durableMemory = try await session.inspection.durableMemory()
        try await session.maintenance.importHistory(
            history,
            durableMemory: durableMemory,
            replaceExisting: true
        )
    }

    private func dropLastAssistantTurnIfNeeded(in session: ContextSession) async throws {
        var history = try await session.inspection.history()
        guard let lastTurn = history.last, lastTurn.role == .assistant else {
            return
        }

        history.removeLast()
        let durableMemory = try await session.inspection.durableMemory()
        try await session.maintenance.importHistory(
            history,
            durableMemory: durableMemory,
            replaceExisting: true
        )
    }

    private func metadata(for session: ContextSession) async -> WheelTurnMetadata {
        let diagnostics = await session.inspection.diagnostics()
        return WheelTurnMetadata(
            compaction: diagnostics?.lastCompaction,
            bridge: diagnostics?.lastBridge
        )
    }

    private func logPlainTextRequestTrace(
        route: String,
        sessionID: String,
        strategy: PlainTextGenerationStrategy,
        prompt: String
    ) async {
        guard let runtime = await runtimeConfiguration(for: sessionID) else {
            Log.Services.debug("\(route): missing runtime configuration for id=\(sessionID)")
            return
        }

        let endpoint = runtime.inference
        let baseURLHost = endpoint.options["baseURL"]
            .flatMap(URL.init(string:))
            .flatMap(\.host) ?? "n/a"
        let overrideText = endpoint.contextWindowOverride.map(String.init) ?? "default"
        let strategyLabel: String = switch strategy {
        case .streaming:
            "streaming"
        case .oneShot:
            "oneShot"
        }
        Log.Services.debug(
            "\(route): request trace id=\(sessionID), backend=\(endpoint.backendID), model=\(endpoint.modelID), host=\(baseURLHost), strategy=\(strategyLabel), contextWindowOverride=\(overrideText), promptChars=\(prompt.count), requestedMaximumResponseTokens=\(budgetPolicy.reservedOutputTokens)"
        )
    }

    private func logSessionDiagnostics(
        route: String,
        session: ContextSession,
        responseLength: Int
    ) async {
        guard let diagnostics = await session.inspection.diagnostics() else {
            Log.Services.debug("\(route): missing diagnostics for id=\(session.id), responseChars=\(responseLength)")
            return
        }

        guard let budget = diagnostics.lastBudget else {
            Log.Services.debug(
                "\(route): diagnostics id=\(session.id), windowIndex=\(diagnostics.windowIndex), responseChars=\(responseLength), budget=missing"
            )
            return
        }

        let breakdown = budget.breakdown
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ",")

        Log.Services.debug(
            "\(route): diagnostics id=\(session.id), windowIndex=\(diagnostics.windowIndex), responseChars=\(responseLength), contextWindowTokens=\(budget.contextWindowTokens), estimatedInputTokens=\(budget.estimatedInputTokens), reservedOutputTokens=\(budget.reservedOutputTokens), projectedTotalTokens=\(budget.projectedTotalTokens), softLimitTokens=\(budget.softLimitTokens), emergencyLimitTokens=\(budget.emergencyLimitTokens), breakdown=\(breakdown)"
        )
    }

    private func mapReply<Content: Sendable>(
        _ response: StructuredReply<Content>,
        transcriptRenderer: (@Sendable (Content) -> String)? = nil,
        modelDisplayName: String
    ) -> WheelGeneratedReply<Content> {
        WheelGeneratedReply(
            value: response.value,
            transcriptText: transcriptRenderer?(response.value) ?? response.transcriptText,
            metadata: WheelTurnMetadata(
                compaction: response.metadata.compaction,
                bridge: response.metadata.bridge
            ),
            modelDisplayName: modelDisplayName
        )
    }

    private func ensureBootstrappedRuntime() async {
        guard didBootstrapRuntime == false else {
            return
        }

        Log.Services.info("Bootstrapping LanguageModelKit runtime at \(storageRootURL.path)")
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            await runtimeRegistry.register(AppleInferenceBackend())
        }
        await runtimeRegistry.register(OpenAIInferenceBackend())
        await runtimeRegistry.register(VLLMInferenceBackend())
        didBootstrapRuntime = true
        Log.Services.info("LanguageModelKit runtime bootstrapped")
    }

    private func modelDisplayName(for sessionID: String) async -> String {
        if let runtime = liveSessionRuntimes[sessionID] {
            return Self.displayName(for: runtime.inference)
        }

        guard let state = try? await threadStore.load(threadID: sessionID) else {
            Log.Services.debug("modelDisplayName: no persisted state for id=\(sessionID); falling back to current profile")
            return modelConfigurationProvider.currentProfile().displayName
        }

        return Self.displayName(for: state.runtime.inference)
    }

    nonisolated static func usesStreamingTextCompatibility(
        for providerID: WheelModelProviderID
    ) -> Bool {
        switch providerID {
        case .apple, .openAI, .vllm:
            return true
        }
    }

    private func structuredGenerationStrategy(for sessionID: String) async -> StructuredGenerationStrategy {
        if Self.usesStreamingTextCompatibility(for: await providerID(for: sessionID)) {
            return .streamingTextCompatibility
        }
        return .oneShotTextCompatibility
    }

    private func plainTextGenerationStrategy(for sessionID: String) async -> PlainTextGenerationStrategy {
        if await supportsPlainTextStreaming(for: sessionID) {
            return .streaming
        }
        return .oneShot
    }

    private func compatibleSpec<Value: Sendable>(
        _ spec: StructuredOutputSpec<Value>,
        for sessionID: String
    ) async -> StructuredOutputSpec<Value> {
        guard await providerID(for: sessionID) == .apple else {
            return spec
        }

        let schema = WheelOutputSchema.removingStringLengthConstraints(from: spec.schema)
        Log.Services.debug("compatibleSpec: removed unsupported Apple string length constraints for id=\(sessionID)")
        return StructuredOutputSpec(
            schema: schema,
            decode: spec.decode,
            transcriptRenderer: spec.transcriptRenderer
        )
    }

    private func providerID(for sessionID: String) async -> WheelModelProviderID {
        if let runtime = liveSessionRuntimes[sessionID],
           let providerID = WheelModelProviderID(rawValue: runtime.inference.backendID) {
            return providerID
        }

        if let state = try? await threadStore.load(threadID: sessionID),
           let providerID = WheelModelProviderID(rawValue: state.runtime.inference.backendID) {
            return providerID
        }

        return modelConfigurationProvider.currentProfile().providerID
    }

    private func supportsPlainTextStreaming(for sessionID: String) async -> Bool {
        await ensureBootstrappedRuntime()

        guard let runtime = await runtimeConfiguration(for: sessionID) else {
            return true
        }

        let availability = await contextManager.availability(for: runtime.inference)
        switch availability.status {
        case .available:
            return availability.capabilities.supportsTextStreaming
        case .unavailable:
            return true
        }
    }

    private func runtimeConfiguration(for sessionID: String) async -> ThreadRuntimeConfiguration? {
        if let runtime = liveSessionRuntimes[sessionID] {
            return runtime
        }

        if let state = try? await threadStore.load(threadID: sessionID) {
            return state.runtime
        }

        return nil
    }

    nonisolated static func isUnsupportedTextStreaming(_ error: RuntimeError) -> Bool {
        if case .unsupportedCapability = error {
            return true
        }
        return false
    }

    private static func defaultStructuredBackends() -> [String: any StructuredOutputBackend] {
        var backends: [String: any StructuredOutputBackend] = [
            WheelModelProviderID.openAI.rawValue: OpenAIStructuredOutputBackend(),
            WheelModelProviderID.vllm.rawValue: VLLMStructuredOutputBackend(),
        ]

        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            backends[WheelModelProviderID.apple.rawValue] = AppleStructuredOutputBackend()
        }

        return backends
    }

    private static func displayName(for endpoint: ModelEndpoint) -> String {
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

    nonisolated static func summarySessionID(for requestID: UUID) -> String {
        "summary:\(requestID.uuidString.lowercased())"
    }

    nonisolated static func agentCompletionSessionID(for requestID: UUID) -> String {
        "agent-completion:\(requestID.uuidString.lowercased())"
    }

    nonisolated static func widgetSessionID(for requestID: UUID) -> String {
        "widget:\(requestID.uuidString.lowercased())"
    }
}
