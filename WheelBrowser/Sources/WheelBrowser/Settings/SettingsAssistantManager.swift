import Foundation
import Observation

@MainActor
@Observable
final class SettingsAssistantManager {
    static let shared = SettingsAssistantManager(
        orchestrator: .shared,
        registry: .shared,
        runtimeCoordinator: SettingsRuntimeCoordinator.shared
    )

    var messages: [ChatMessage] = []
    var composerText: String = ""
    var isSending: Bool = false
    var error: String?
    var pendingPlan: SettingsAssistantPendingPlan?

    private let orchestrator: SettingsAssistantOrchestrator
    private let registry: SettingsCapabilityRegistry
    private let runtimeCoordinator: any SettingsRuntimeCoordinating

    @ObservationIgnored private var settingsConversationID = UUID()
    @ObservationIgnored private var generalConversationID = UUID()

    init(
        orchestrator: SettingsAssistantOrchestrator,
        registry: SettingsCapabilityRegistry,
        runtimeCoordinator: any SettingsRuntimeCoordinating
    ) {
        self.orchestrator = orchestrator
        self.registry = registry
        self.runtimeCoordinator = runtimeCoordinator
    }

    var canSendPrompt: Bool {
        !isSending && pendingPlan == nil
    }

    func submitComposerPrompt() async {
        await submitPrompt(composerText)
    }

    func submitPrompt(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard pendingPlan == nil else {
            error = "Confirm or cancel the pending settings changes before sending another request."
            return
        }

        guard !isSending else { return }

        let priorMessages = messages
        composerText = ""
        error = nil
        isSending = true

        let userMessage = ChatMessage(
            role: .user,
            content: trimmed,
            timestamp: Date()
        )
        messages.append(userMessage)

        do {
            let preparedTurn = try await orchestrator.prepareTurn(
                prompt: trimmed,
                visibleMessages: priorMessages,
                settingsConversationID: settingsConversationID,
                generalConversationID: generalConversationID
            )

            switch preparedTurn {
            case .reply(let reply):
                updateUserMessage(id: userMessage.id, modelDisplayName: reply.modelDisplayName)
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        content: reply.message,
                        timestamp: Date(),
                        modelUsed: reply.modelDisplayName
                    )
                )
                pendingPlan = reply.pendingPlan

            case .generalChat(let stream, _):
                await handleGeneralChatStream(
                    stream,
                    userMessageID: userMessage.id
                )
            }
        } catch {
            messages.append(
                ChatMessage(
                    role: .assistant,
                    content: "Error: \(Self.userFacingErrorMessage(for: error))",
                    timestamp: Date(),
                    isFailed: true
                )
            )
            self.error = Self.userFacingErrorMessage(for: error)
        }

        isSending = false
    }

    func confirmPendingPlan() async {
        guard let pendingPlan, !isSending else { return }

        isSending = true
        error = nil
        self.pendingPlan = nil

        messages.append(
            ChatMessage(
                role: .user,
                content: "Confirm the proposed settings changes.",
                timestamp: Date()
            )
        )

        let report = await registry.applyValidatedActions(
            pendingPlan.actions,
            coordinator: runtimeCoordinator
        )

        messages.append(
            ChatMessage(
                role: .assistant,
                content: formattedApplyReport(report),
                timestamp: Date(),
                modelUsed: pendingPlan.modelDisplayName
            )
        )

        isSending = false
    }

    func cancelPendingPlan() {
        guard pendingPlan != nil, !isSending else { return }

        pendingPlan = nil
        error = nil
        messages.append(
            ChatMessage(
                role: .user,
                content: "Cancel the proposed settings changes.",
                timestamp: Date()
            )
        )
        messages.append(
            ChatMessage(
                role: .assistant,
                content: "Cancelled. No settings were changed.",
                timestamp: Date()
            )
        )
    }

    private func handleGeneralChatStream(
        _ stream: AsyncThrowingStream<WheelChatStreamEvent, Error>,
        userMessageID: UUID
    ) async {
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            timestamp: Date(),
            isStreaming: true
        )
        let assistantMessageID = assistantMessage.id
        messages.append(assistantMessage)

        do {
            var latestResponse: WheelGeneratedReply<GeneratedChatAssistantResponse>?
            var latestAnswer = ""

            for try await event in stream {
                switch event {
                case .thinking:
                    continue
                case .partial(let answer):
                    latestAnswer = answer
                    updateAssistantMessage(
                        id: assistantMessageID,
                        content: latestAnswer,
                        isStreaming: true
                    )

                case .completed(let response):
                    latestResponse = response
                    latestAnswer = response.value.answer
                }
            }

            guard let latestResponse else {
                throw SettingsAssistantOrchestratorError.noGeneralModelAvailable(
                    "The general chat model returned no response."
                )
            }

            let trimmedAnswer = latestAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let followUps = FollowUpSuggestionNormalizer.normalize(latestResponse.value.suggestions)
            let artifacts = ArtifactExtractor.extract(from: trimmedAnswer)

            updateUserMessage(
                id: userMessageID,
                modelDisplayName: latestResponse.modelDisplayName
            )
            updateAssistantMessage(
                id: assistantMessageID,
                content: trimmedAnswer,
                isStreaming: false,
                modelDisplayName: latestResponse.modelDisplayName,
                suggestedFollowUps: followUps,
                artifacts: artifacts
            )
        } catch {
            updateAssistantMessage(
                id: assistantMessageID,
                content: "Error: \(Self.userFacingErrorMessage(for: error))",
                isStreaming: false,
                isFailed: true
            )
            self.error = Self.userFacingErrorMessage(for: error)
        }
    }

    private func updateUserMessage(id: UUID, modelDisplayName: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].modelUsed = modelDisplayName
    }

    private func updateAssistantMessage(
        id: UUID,
        content: String,
        isStreaming: Bool,
        modelDisplayName: String? = nil,
        suggestedFollowUps: [String] = [],
        artifacts: [ChatArtifact] = [],
        isFailed: Bool = false
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].isStreaming = isStreaming
        messages[index].isFailed = isFailed
        if let modelDisplayName {
            messages[index].modelUsed = modelDisplayName
        }
        if !suggestedFollowUps.isEmpty {
            messages[index].suggestedFollowUps = suggestedFollowUps
        }
        if !artifacts.isEmpty {
            messages[index].artifacts = artifacts
        }
    }

    private func formattedApplyReport(_ report: SettingsApplyReport) -> String {
        var sections: [String] = []

        if !report.appliedActions.isEmpty {
            sections.append(
                """
                Applied changes:
                \(report.appliedActions.map { "- \($0.preview)" }.joined(separator: "\n"))
                """
            )
        }

        if !report.failedActions.isEmpty {
            sections.append(
                """
                Failed changes:
                \(report.failedActions.map { "- \($0.action.displayName): \($0.message)" }.joined(separator: "\n"))
                """
            )
        }

        if sections.isEmpty {
            return "No settings were changed."
        }

        return sections.joined(separator: "\n\n")
    }

    static func userFacingErrorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}
