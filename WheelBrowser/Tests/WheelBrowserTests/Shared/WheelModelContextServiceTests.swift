import Foundation
import LanguageModelContextKit
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

    @Test("Session existence checks use persisted LMCK state")
    func sessionExistsTracksPersistedState() async throws {
        let threadStore = InMemoryThreadStore()
        let service = makeService(threadStore: threadStore)
        let conversationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let sessionID = WheelModelContextService.chatSessionID(for: conversationID)

        #expect(await service.sessionExists(sessionID: sessionID) == false)

        try await service.openChatSession(
            conversationId: conversationID,
            instructions: "Reply concisely."
        )

        #expect(await service.sessionExists(sessionID: sessionID) == true)
    }

    @Test("Appending an agent tool turn uses the active session window index")
    func appendAgentToolTurnUsesCurrentWindowIndex() async throws {
        let threadStore = InMemoryThreadStore()
        let service = makeService(threadStore: threadStore)
        let sessionID = "agent:11111111-2222-3333-4444-555555555555:66666666-7777-8888-9999-aaaaaaaaaaaa"

        try await threadStore.save(
            PersistedThreadState(
                threadID: sessionID,
                instructions: "Use tools to browse and report results.",
                localeIdentifier: nil,
                model: .default,
                activeWindowIndex: 4
            ),
            threadID: sessionID
        )

        try await service.appendAgentToolTurn(
            text: "Clicked the pagination link.",
            tags: ["tool", "pagination"],
            sessionID: sessionID
        )

        let state = try await threadStore.load(threadID: sessionID)
        #expect(state?.turns.count == 1)
        #expect(state?.turns.last?.windowIndex == 4)
        #expect(state?.turns.last?.role == .tool)
        #expect(state?.turns.last?.tags == ["tool", "pagination"])
    }

    private func makeService(
        threadStore: any ThreadStore
    ) -> WheelModelContextService {
        let configuration = ContextManagerConfiguration(
            persistence: PersistencePolicy(
                threads: threadStore,
                memories: InMemoryMemoryStore(),
                blobs: InMemoryBlobStore(),
                retriever: nil
            )
        )
        return WheelModelContextService(
            storageRootURL: URL(fileURLWithPath: "/tmp/WheelModelContextServiceTests", isDirectory: true),
            configuration: configuration
        )
    }
}
