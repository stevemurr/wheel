import Foundation
import FoundationModels
import LanguageModelContextKit

typealias LMContextKit = LanguageModelContextKit
typealias LMContextConfiguration = ContextManagerConfiguration
typealias LMThreadConfiguration = ThreadConfiguration
typealias LMAvailabilityStatus = AvailabilityStatus
typealias LMBudgetPolicy = BudgetPolicy
typealias LMPersistencePolicy = PersistencePolicy
typealias LMManagedStructuredResponse<Content: Generable> = ManagedStructuredResponse<Content>
typealias LMManagedTextResponse = ManagedTextResponse
typealias LMManagedStructuredStreamEvent<Content: Generable> = ManagedStructuredStreamEvent<Content>
typealias LMNormalizedTurn = NormalizedTurn
typealias LMDurableMemoryRecord = DurableMemoryRecord
typealias LMPersistedThreadState = PersistedThreadState

enum WheelChatStreamEvent: Sendable {
    case partial(answer: String)
    case completed(LMManagedStructuredResponse<GeneratedChatAssistantResponse>)
}

enum WheelAgentDecisionStreamEvent: Sendable {
    case partialThought(String)
    case completed(LMManagedStructuredResponse<GeneratedAgentDecision>)
}

enum WheelSummaryStreamEvent: Sendable {
    case partial(summary: String)
    case completed(LMManagedStructuredResponse<GeneratedSummaryResponse>)
}

protocol WheelModelContextServing: Sendable {
    func availabilityStatus() async -> LMAvailabilityStatus
    func openChatThread(conversationId: UUID, instructions: String) async throws
    func importChatThread(
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
    func openAgentThread(tabId: UUID, runId: UUID, instructions: String) async throws -> String
    func streamAgentDecision(
        prompt: String,
        threadID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error>
    func appendAgentTurns(_ turns: [LMNormalizedTurn], threadID: String) async throws
    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> LMManagedStructuredResponse<GeneratedSummaryResponse>
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
    ) async throws -> LMManagedStructuredResponse<GeneratedWidgetPlan>
    func threadState(threadID: String) async throws -> LMPersistedThreadState
    func resetThread(threadID: String) async throws
}

actor WheelModelContextService: WheelModelContextServing {
    static let shared = WheelModelContextService()

    nonisolated let storageRootURL: URL

    private let contextKit: LMContextKit

    init(
        storageRootURL: URL = FileManager.appSupportDirectory.appendingPathComponent(
            "LanguageModelContextKit",
            isDirectory: true
        ),
        configuration: LMContextConfiguration? = nil
    ) {
        self.storageRootURL = storageRootURL

        if let configuration {
            self.contextKit = LMContextKit(configuration: configuration)
            return
        }

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

        let managedConfiguration = LMContextConfiguration(
            budget: LMBudgetPolicy(defaultContextWindowTokens: 4096),
            persistence: persistence
        )
        self.contextKit = LMContextKit(configuration: managedConfiguration)
    }

    func availabilityStatus() async -> LMAvailabilityStatus {
        await contextKit.availabilityStatus()
    }

    func openChatThread(conversationId: UUID, instructions: String) async throws {
        try await openThread(
            id: Self.chatThreadID(for: conversationId),
            instructions: instructions
        )
    }

    func importChatThread(
        conversationId: UUID,
        instructions: String,
        turns: [LMNormalizedTurn],
        durableMemory: [LMDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {
        try await contextKit.importThread(
            id: Self.chatThreadID(for: conversationId),
            configuration: LMThreadConfiguration(instructions: instructions),
            turns: turns,
            durableMemory: durableMemory,
            replaceExisting: replaceExisting
        )
    }

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        let stream = await contextKit.streamManaged(
            to: prompt,
            generating: GeneratedChatAssistantResponse.self,
            threadID: Self.chatThreadID(for: conversationId),
            transcriptRenderer: { $0.answer }
        )

        return mapChatStream(stream)
    }

    func openAgentThread(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        let threadID = Self.agentThreadID(tabId: tabId, runId: runId)
        try await openThread(id: threadID, instructions: instructions)
        return threadID
    }

    func streamAgentDecision(
        prompt: String,
        threadID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        let stream = await contextKit.streamManaged(
            to: prompt,
            generating: GeneratedAgentDecision.self,
            threadID: threadID,
            transcriptRenderer: { $0.transcriptSummary }
        )

        return mapAgentStream(stream)
    }

    func appendAgentTurns(_ turns: [LMNormalizedTurn], threadID: String) async throws {
        try await contextKit.appendTurns(turns, threadID: threadID)
    }

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> LMManagedStructuredResponse<GeneratedSummaryResponse> {
        try await openSummaryThread(requestID: requestID, instructions: instructions)
        return try await contextKit.respondManaged(
            to: prompt,
            generating: GeneratedSummaryResponse.self,
            threadID: Self.summaryThreadID(for: requestID),
            transcriptRenderer: { $0.summary }
        )
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        try await openSummaryThread(requestID: requestID, instructions: instructions)
        let stream = await contextKit.streamManaged(
            to: prompt,
            generating: GeneratedSummaryResponse.self,
            threadID: Self.summaryThreadID(for: requestID),
            transcriptRenderer: { $0.summary }
        )
        return mapSummaryStream(stream)
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)? = nil
    ) async throws -> LMManagedStructuredResponse<GeneratedWidgetPlan> {
        try await openWidgetThread(requestID: requestID, instructions: instructions)
        return try await contextKit.respondManaged(
            to: prompt,
            generating: GeneratedWidgetPlan.self,
            threadID: Self.widgetThreadID(for: requestID),
            transcriptRenderer: transcriptRenderer
        )
    }

    func threadState(threadID: String) async throws -> LMPersistedThreadState {
        try await contextKit.threadState(threadID: threadID)
    }

    func resetThread(threadID: String) async throws {
        try await contextKit.resetThread(threadID: threadID)
    }

    private func openSummaryThread(requestID: UUID, instructions: String) async throws {
        try await openThread(
            id: Self.summaryThreadID(for: requestID),
            instructions: instructions
        )
    }

    private func openWidgetThread(requestID: UUID, instructions: String) async throws {
        try await openThread(
            id: Self.widgetThreadID(for: requestID),
            instructions: instructions
        )
    }

    private func openThread(id: String, instructions: String) async throws {
        try await contextKit.openThread(
            id: id,
            configuration: LMThreadConfiguration(instructions: instructions)
        )
    }

    private func mapChatStream(
        _ stream: AsyncThrowingStream<LMManagedStructuredStreamEvent<GeneratedChatAssistantResponse>, Error>
    ) -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .partial(let partial, _):
                            guard let answer = partial.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !answer.isEmpty else {
                                continue
                            }
                            continuation.yield(.partial(answer: answer))
                        case .completed(let response):
                            continuation.yield(.completed(response))
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
        _ stream: AsyncThrowingStream<LMManagedStructuredStreamEvent<GeneratedAgentDecision>, Error>
    ) -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .partial(let partial, _):
                            guard let thought = partial.thought?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !thought.isEmpty else {
                                continue
                            }
                            continuation.yield(.partialThought(thought))
                        case .completed(let response):
                            continuation.yield(.completed(response))
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
        _ stream: AsyncThrowingStream<LMManagedStructuredStreamEvent<GeneratedSummaryResponse>, Error>
    ) -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .partial(let partial, _):
                            guard let summary = partial.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !summary.isEmpty else {
                                continue
                            }
                            continuation.yield(.partial(summary: summary))
                        case .completed(let response):
                            continuation.yield(.completed(response))
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

    nonisolated static func chatThreadID(for conversationId: UUID) -> String {
        "chat:\(conversationId.uuidString.lowercased())"
    }

    nonisolated static func agentThreadID(tabId: UUID, runId: UUID) -> String {
        "agent:\(tabId.uuidString.lowercased()):\(runId.uuidString.lowercased())"
    }

    nonisolated static func summaryThreadID(for requestID: UUID) -> String {
        "summary:\(requestID.uuidString.lowercased())"
    }

    nonisolated static func widgetThreadID(for requestID: UUID) -> String {
        "widget:\(requestID.uuidString.lowercased())"
    }
}
