import Foundation
import FoundationModels
import LanguageModelContextKit

typealias LMContextKit = LanguageModelContextKit
typealias LMContextConfiguration = ContextManagerConfiguration
typealias LMSessionConfiguration = SessionConfiguration
typealias LMAvailabilityStatus = AvailabilityStatus
typealias LMBudgetPolicy = BudgetPolicy
typealias LMPersistencePolicy = PersistencePolicy
typealias LMGeneratedReply<Content: Generable> = GeneratedReply<Content>
typealias LMGeneratedStreamEvent<Content: Generable> = GeneratedStreamEvent<Content>
typealias LMNormalizedTurn = NormalizedTurn
typealias LMDurableMemoryRecord = DurableMemoryRecord

struct WheelTurnMetadata: Sendable {
    let compaction: CompactionReport?
    let bridge: BridgeReport?
}

struct WheelGeneratedReply<Value: Sendable>: Sendable {
    let value: Value
    let transcriptText: String
    let metadata: WheelTurnMetadata
}

enum WheelChatStreamEvent: Sendable {
    case partial(answer: String)
    case completed(WheelGeneratedReply<GeneratedChatAssistantResponse>)
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
    func availabilityStatus() async -> LMAvailabilityStatus
    func openChatSession(conversationId: UUID, instructions: String) async throws
    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [LMNormalizedTurn],
        durableMemory: [LMDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws
    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error>
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

    nonisolated let storageRootURL: URL

    private let contextKit: LMContextKit
    private let threadStore: any ThreadStore
    private var sessionConfigurations: [String: LMSessionConfiguration] = [:]

    init(
        storageRootURL: URL = FileManager.appSupportDirectory.appendingPathComponent(
            "LanguageModelContextKit",
            isDirectory: true
        ),
        configuration: LMContextConfiguration? = nil
    ) {
        self.storageRootURL = storageRootURL

        let managedConfiguration: LMContextConfiguration
        if let configuration {
            managedConfiguration = configuration
        } else {
            let persistence = LMPersistencePolicy(
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

            managedConfiguration = LMContextConfiguration(
                budget: LMBudgetPolicy(defaultContextWindowTokens: 4096),
                persistence: persistence
            )
        }

        self.threadStore = managedConfiguration.persistence.threads
        self.contextKit = LMContextKit(configuration: managedConfiguration)
    }

    func availabilityStatus() async -> LMAvailabilityStatus {
        await contextKit.availability()
    }

    func openChatSession(conversationId: UUID, instructions: String) async throws {
        _ = try await openSession(
            id: Self.chatSessionID(for: conversationId),
            instructions: instructions
        )
    }

    func importChatSession(
        conversationId: UUID,
        instructions: String,
        turns: [LMNormalizedTurn],
        durableMemory: [LMDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {
        let session = try await openSession(
            id: Self.chatSessionID(for: conversationId),
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
        let session = try await resolveSession(id: Self.chatSessionID(for: conversationId))
        return mapChatStream(session.stream(prompt, as: GeneratedChatAssistantResponse.self))
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
        let session = try await openSession(
            id: Self.agentIntentSessionID(for: requestID),
            instructions: instructions
        )
        let response = try await session.reply(to: task, as: GeneratedAgentTaskIntent.self)
        return mapReply(response) { _ in
            "Agent task intent extracted"
        }
    }

    func streamAgentDecision(
        prompt: String,
        sessionID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        let session = try await resolveSession(id: sessionID)
        return mapAgentStream(session.stream(prompt, as: GeneratedAgentDecision.self))
    }

    func generateAgentCompletionEvaluation(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedAgentCompletionEvaluation> {
        let session = try await openSession(
            id: Self.agentCompletionSessionID(for: requestID),
            instructions: instructions
        )
        let response = try await session.reply(to: prompt, as: GeneratedAgentCompletionEvaluation.self)
        return mapReply(response) { response in
            response.isComplete ? "Completion accepted" : "Completion rejected"
        }
    }

    func appendAgentToolTurn(text: String, tags: [String], sessionID: String) async throws {
        let session = try await resolveSession(id: sessionID)

        guard let diagnostics = await session.inspection.diagnostics() else {
            throw LanguageModelContextKitError.threadNotFound(sessionID)
        }

        let turn = LMNormalizedTurn(
            role: .tool,
            text: text,
            priority: 700,
            tags: tags,
            windowIndex: diagnostics.windowIndex
        )
        try await session.maintenance.appendTurns([turn])
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> WheelGeneratedReply<GeneratedSummaryResponse> {
        let session = try await openSession(
            id: Self.summarySessionID(for: requestID),
            instructions: instructions
        )
        let response = try await session.reply(to: prompt, as: GeneratedSummaryResponse.self)
        return mapReply(response) { $0.summary }
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        let session = try await openSession(
            id: Self.summarySessionID(for: requestID),
            instructions: instructions
        )
        return mapSummaryStream(session.stream(prompt, as: GeneratedSummaryResponse.self))
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)? = nil
    ) async throws -> WheelGeneratedReply<GeneratedWidgetPlan> {
        let session = try await openSession(
            id: Self.widgetSessionID(for: requestID),
            instructions: instructions
        )
        let response = try await session.reply(to: prompt, as: GeneratedWidgetPlan.self)
        return mapReply(response, transcriptRenderer: transcriptRenderer)
    }

    func sessionExists(sessionID: String) async -> Bool {
        (try? await threadStore.load(threadID: sessionID)) != nil
    }

    func resetSession(sessionID: String) async throws {
        let session = try await resolveSession(id: sessionID)
        try await session.maintenance.reset()
        sessionConfigurations.removeValue(forKey: sessionID)
    }

    private func openSession(
        id: String,
        instructions: String
    ) async throws -> ContextSession {
        try await openSession(
            id: id,
            configuration: LMSessionConfiguration(instructions: instructions)
        )
    }

    private func openSession(
        id: String,
        configuration: LMSessionConfiguration
    ) async throws -> ContextSession {
        let session = try await contextKit.session(id: id, configuration: configuration)
        sessionConfigurations[id] = configuration
        return session
    }

    private func resolveSession(id: String) async throws -> ContextSession {
        let configuration = try await sessionConfiguration(for: id)
        return try await openSession(id: id, configuration: configuration)
    }

    private func sessionConfiguration(for id: String) async throws -> LMSessionConfiguration {
        if let configuration = sessionConfigurations[id] {
            return configuration
        }

        guard let state = try await threadStore.load(threadID: id) else {
            throw LanguageModelContextKitError.threadNotFound(id)
        }

        let configuration = LMSessionConfiguration(
            instructions: state.instructions,
            locale: state.localeIdentifier.map(Locale.init(identifier:)),
            model: state.model
        )
        sessionConfigurations[id] = configuration
        return configuration
    }

    private func mapReply<Content: Generable & Sendable>(
        _ response: LMGeneratedReply<Content>,
        transcriptRenderer: (@Sendable (Content) -> String)? = nil
    ) -> WheelGeneratedReply<Content> {
        WheelGeneratedReply(
            value: response.value,
            transcriptText: transcriptRenderer?(response.value) ?? response.transcriptText,
            metadata: WheelTurnMetadata(
                compaction: response.metadata.compaction,
                bridge: response.metadata.bridge
            )
        )
    }

    private func mapChatStream(
        _ stream: AsyncThrowingStream<LMGeneratedStreamEvent<GeneratedChatAssistantResponse>, Error>
    ) -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .partial(let partial):
                            guard let answer = partial.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !answer.isEmpty else {
                                continue
                            }
                            continuation.yield(.partial(answer: answer))
                        case .completed(let response):
                            continuation.yield(
                                .completed(mapReply(response, transcriptRenderer: { $0.answer }))
                            )
                        }
                    }
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

    private func mapAgentStream(
        _ stream: AsyncThrowingStream<LMGeneratedStreamEvent<GeneratedAgentDecision>, Error>
    ) -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .partial(let partial):
                            guard let thought = partial.thought?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !thought.isEmpty else {
                                continue
                            }
                            continuation.yield(.partialThought(thought))
                        case .completed(let response):
                            continuation.yield(
                                .completed(mapReply(response, transcriptRenderer: { $0.transcriptSummary }))
                            )
                        }
                    }
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

    private func mapSummaryStream(
        _ stream: AsyncThrowingStream<LMGeneratedStreamEvent<GeneratedSummaryResponse>, Error>
    ) -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .partial(let partial):
                            guard let summary = partial.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !summary.isEmpty else {
                                continue
                            }
                            continuation.yield(.partial(summary: summary))
                        case .completed(let response):
                            continuation.yield(
                                .completed(mapReply(response, transcriptRenderer: { $0.summary }))
                            )
                        }
                    }
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
