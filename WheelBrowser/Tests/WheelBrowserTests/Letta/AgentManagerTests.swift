import Foundation
import LanguageModelContextKit
import Testing
@testable import WheelBrowser

@MainActor
@Suite("AgentManager")
struct AgentManagerTests {
    @Test("Maps LM generation failures to a readable message")
    func mapsGenerationFailures() {
        let message = AgentManager.userFacingErrorMessage(
            for: LanguageModelContextKitError.generationFailed("Streaming finished without completion")
        )

        #expect(message == "Streaming finished without completion")
    }

    @Test("Maps LM budget failures to context guidance")
    func mapsBudgetFailures() {
        let diagnostics = ThreadDiagnostics(
            threadID: "chat-thread",
            windowIndex: 0,
            lastBudget: nil,
            lastCompaction: nil,
            lastBridge: nil,
            turnCount: 12,
            durableMemoryCount: 0,
            blobCount: 0
        )

        let message = AgentManager.userFacingErrorMessage(
            for: LanguageModelContextKitError.budgetExhausted(diagnostics)
        )

        #expect(message == "The chat ran out of context budget. Start a new conversation or remove some attached context.")
    }
}
