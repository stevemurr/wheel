import Foundation

enum SettingsAssistantBackend: String, Sendable {
    case appleSettings
    case configuredGeneralChat
    case appleGeneralFallback
}

struct SettingsAssistantPendingPlan: Equatable, Sendable {
    let warnings: [String]
    let actions: [ValidatedSettingsAction]
    let modelDisplayName: String
    let source: SettingsAssistantBackend
}

struct SettingsAssistantImmediateReply: Equatable, Sendable {
    let message: String
    let modelDisplayName: String
    let source: SettingsAssistantBackend
    let pendingPlan: SettingsAssistantPendingPlan?
}

enum SettingsAssistantPreparedTurn {
    case reply(SettingsAssistantImmediateReply)
    case generalChat(
        stream: AsyncThrowingStream<WheelChatStreamEvent, Error>,
        source: SettingsAssistantBackend
    )
}

enum SettingsAssistantOrchestratorError: LocalizedError, Equatable {
    case appleModelUnavailable(String)
    case noGeneralModelAvailable(String)

    var errorDescription: String? {
        switch self {
        case .appleModelUnavailable(let message):
            return message
        case .noGeneralModelAvailable(let message):
            return message
        }
    }
}

@MainActor
final class SettingsAssistantOrchestrator {
    static let shared = SettingsAssistantOrchestrator(
        appleContextService: WheelModelContextService.settingsAssistantApple,
        generalContextService: WheelModelContextService.shared,
        registry: .shared
    )

    private let appleContextService: any WheelModelContextServing
    private let generalContextService: any WheelModelContextServing
    private let registry: SettingsCapabilityRegistry

    init(
        appleContextService: any WheelModelContextServing,
        generalContextService: any WheelModelContextServing,
        registry: SettingsCapabilityRegistry
    ) {
        self.appleContextService = appleContextService
        self.generalContextService = generalContextService
        self.registry = registry
    }

    func prepareTurn(
        prompt: String,
        visibleMessages: [ChatMessage],
        settingsConversationID: UUID,
        generalConversationID: UUID
    ) async throws -> SettingsAssistantPreparedTurn {
        let appleAvailability = await appleContextService.availabilityStatus()
        guard appleAvailability.isAvailable else {
            throw SettingsAssistantOrchestratorError.appleModelUnavailable(
                appleAvailability.reason ?? "The Apple model is unavailable, so the Settings Assistant cannot classify this request."
            )
        }

        try await syncTranscript(
            visibleMessages,
            conversationID: settingsConversationID,
            instructions: SettingsAssistantPromptBuilder.settingsTrackInstructions,
            service: appleContextService
        )

        let decision = try await appleContextService.generateSettingsRouteDecision(
            conversationId: settingsConversationID,
            prompt: SettingsAssistantPromptBuilder.routePrompt(
                userPrompt: prompt,
                registry: registry
            )
        )

        switch decision.value.normalizedRoute {
        case .settingsReport, .settingsMutation:
            try await syncTranscript(
                visibleMessages,
                conversationID: settingsConversationID,
                instructions: SettingsAssistantPromptBuilder.settingsTrackInstructions,
                service: appleContextService
            )

            let plan = try await appleContextService.generateSettingsPlan(
                conversationId: settingsConversationID,
                prompt: SettingsAssistantPromptBuilder.settingsPlanPrompt(
                    userPrompt: prompt,
                    route: decision.value.normalizedRoute,
                    registry: registry
                )
            )

            let validatedActions = try registry.validate(actions: plan.value.actions)
            let pendingPlan = validatedActions.isEmpty
                ? nil
                : SettingsAssistantPendingPlan(
                    warnings: plan.value.warnings,
                    actions: validatedActions,
                    modelDisplayName: plan.modelDisplayName,
                    source: .appleSettings
                )

            return .reply(
                SettingsAssistantImmediateReply(
                    message: formattedSettingsReply(
                        reply: plan.value.reply,
                        warnings: plan.value.warnings,
                        pendingPlan: pendingPlan
                    ),
                    modelDisplayName: plan.modelDisplayName,
                    source: .appleSettings,
                    pendingPlan: pendingPlan
                )
            )

        case .generalChat:
            let generalBackend = try await selectGeneralBackend()
            try await syncTranscript(
                visibleMessages,
                conversationID: generalConversationID,
                instructions: SystemPromptConfig.chatPrompt,
                service: generalBackend.service
            )
            let stream = try await generalBackend.service.streamChatResponse(
                conversationId: generalConversationID,
                prompt: prompt
            )
            return .generalChat(stream: stream, source: generalBackend.source)

        case .unsupported:
            return .reply(
                SettingsAssistantImmediateReply(
                    message: SettingsAssistantPromptBuilder.unsupportedReply(
                        for: decision.value,
                        registry: registry
                    ),
                    modelDisplayName: decision.modelDisplayName,
                    source: .appleSettings,
                    pendingPlan: nil
                )
            )
        }
    }

    private func syncTranscript(
        _ messages: [ChatMessage],
        conversationID: UUID,
        instructions: String,
        service: any WheelModelContextServing
    ) async throws {
        try await service.importChatSession(
            conversationId: conversationID,
            instructions: instructions,
            turns: modelVisibleTurns(from: messages),
            durableMemory: [],
            replaceExisting: true
        )
        try await service.openChatSession(
            conversationId: conversationID,
            instructions: instructions
        )
    }

    private func modelVisibleTurns(from messages: [ChatMessage]) -> [WheelNormalizedTurn] {
        messages.compactMap { message in
            guard !message.isStreaming else {
                return nil
            }

            let role: WheelNormalizedTurn.Role
            let priority: Int

            switch message.role {
            case .user:
                role = .user
                priority = 950
            case .assistant:
                role = .assistant
                priority = 800
            case .system:
                role = .system
                priority = 700
            case .thinking:
                return nil
            }

            return WheelNormalizedTurn(
                id: message.id,
                role: role,
                text: message.modelContent ?? message.content,
                createdAt: message.timestamp,
                priority: priority,
                windowIndex: 0
            )
        }
    }

    private func selectGeneralBackend() async throws -> (
        service: any WheelModelContextServing,
        source: SettingsAssistantBackend
    ) {
        let configuredAvailability = await generalContextService.availabilityStatus()
        if configuredAvailability.isAvailable {
            return (generalContextService, .configuredGeneralChat)
        }

        let appleAvailability = await appleContextService.availabilityStatus()
        if appleAvailability.isAvailable {
            return (appleContextService, .appleGeneralFallback)
        }

        throw SettingsAssistantOrchestratorError.noGeneralModelAvailable(
            configuredAvailability.reason
                ?? appleAvailability.reason
                ?? "No configured model or Apple fallback is currently available."
        )
    }

    private func formattedSettingsReply(
        reply: String,
        warnings: [String],
        pendingPlan: SettingsAssistantPendingPlan?
    ) -> String {
        var sections = [reply.trimmingCharacters(in: .whitespacesAndNewlines)]

        if !warnings.isEmpty {
            sections.append(
                """
                Warnings:
                \(warnings.map { "- \($0)" }.joined(separator: "\n"))
                """
            )
        }

        if let pendingPlan, !pendingPlan.actions.isEmpty {
            sections.append(
                """
                Proposed changes:
                \(pendingPlan.actions.map { "- \($0.preview)" }.joined(separator: "\n"))

                Confirm to apply these changes or Cancel to discard them.
                """
            )
        }

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
