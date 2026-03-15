import Foundation

struct WidgetManifestGenerationProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case checkingAvailability
        case generatingManifest
        case repairingManifest
        case validatingManifest
        case preflightingWidget
    }

    let phase: Phase
    let detail: String
}

typealias WidgetManifestGenerationProgressHandler = @Sendable (WidgetManifestGenerationProgress) async -> Void

protocol WidgetManifestGenerator: Sendable {
    func generate(prompt: String, progress: WidgetManifestGenerationProgressHandler?) async throws -> WidgetManifest
}

extension WidgetManifestGenerator {
    func generate(prompt: String) async throws -> WidgetManifest {
        try await generate(prompt: prompt, progress: nil)
    }
}

final class OnDeviceWidgetManifestGenerator: @unchecked Sendable, WidgetManifestGenerator {
    typealias CompletionProvider = @Sendable ([ChatMessage], String) async throws -> GeneratedWidgetPlan
    typealias AvailabilityProvider = @Sendable () async -> WheelModelAvailability
    typealias PreflightProvider = @Sendable (WidgetManifest) async throws -> Void

    private let completionProvider: CompletionProvider?
    private let availabilityProvider: AvailabilityProvider?
    private let preflightProvider: PreflightProvider
    private let contextService: any WheelModelContextServing

    init(
        completionProvider: CompletionProvider? = nil,
        availabilityProvider: AvailabilityProvider? = nil,
        preflightProvider: PreflightProvider? = nil,
        contextService: any WheelModelContextServing = WheelModelContextService.widgetGenerationApple
    ) {
        self.completionProvider = completionProvider
        self.preflightProvider = preflightProvider ?? { manifest in
            try await WidgetManifestPreflightRunner.shared.preflight(manifest)
        }
        self.contextService = contextService
        if let availabilityProvider {
            self.availabilityProvider = availabilityProvider
        } else if completionProvider == nil {
            self.availabilityProvider = {
                await contextService.availabilityStatus()
            }
        } else {
            self.availabilityProvider = nil
        }
    }

    func generate(prompt: String, progress: WidgetManifestGenerationProgressHandler? = nil) async throws -> WidgetManifest {
        if let template = WidgetPromptTemplateFactory.manifest(for: prompt) {
            await report(
                .generatingManifest,
                detail: "Using a built-in template for a reliable widget.",
                to: progress
            )
            await report(
                .validatingManifest,
                detail: "Validating the built-in widget before saving.",
                to: progress
            )
            let validated = try WidgetManifestValidator.validate(template)
            return try await preflight(validated, progress: progress)
        }

        if let planned = WidgetPromptPlanFactory.plan(for: prompt) {
            await report(
                .generatingManifest,
                detail: "Using a built-in planner for a reliable finance or list widget.",
                to: progress
            )
            await report(
                .validatingManifest,
                detail: "Compiling the built-in plan into a widget manifest.",
                to: progress
            )
            let manifest = try buildManifest(from: planned, fallbackPrompt: prompt)
            return try await preflight(manifest, progress: progress)
        }

        if let availabilityProvider {
            await report(
                .checkingAvailability,
                detail: "Checking the Apple on-device model.",
                to: progress
            )
            let availability = await availabilityProvider()
            guard availability.isAvailable else {
                throw WidgetManifestGenerationError.llmFailed(
                    availability.reason ?? "The Apple on-device model is not available."
                )
            }
        }

        let instructions = WidgetPlanSystemPrompt.build()
        let requestID = UUID()
        let usingContextService = completionProvider == nil
        let widgetSessionID = WheelModelContextService.widgetSessionID(for: requestID)
        defer {
            if usingContextService {
                Task {
                    try? await contextService.resetSession(sessionID: widgetSessionID)
                }
            }
        }

        await report(
            .generatingManifest,
            detail: "Drafting a constrained widget plan from your prompt.",
            to: progress
        )
        let response = try await requestPlan(
            messages: [.user(prompt)],
            instructions: instructions,
            requestID: requestID
        )

        do {
            await report(
                .validatingManifest,
                detail: "Compiling the plan into a widget manifest and validating it.",
                to: progress
            )
            let manifest = try buildManifest(from: response, fallbackPrompt: prompt)
            return try await preflight(manifest, progress: progress)
        } catch let error as WidgetManifestGenerationError {
            Log.Widgets.warning("Initial widget plan was invalid, retrying repair: \(error.localizedDescription)")
            Log.Widgets.debug("Widget plan candidate: \(rawPlanDebugString(from: response))")

            do {
                await report(
                    .repairingManifest,
                    detail: "Repairing the widget plan because the first draft was invalid.",
                    to: progress
                )
                let repaired = try await requestPlan(
                    messages: repairMessages(
                        prompt: prompt,
                        response: response,
                        failure: error
                    ),
                    instructions: instructions,
                    requestID: requestID
                )
                await report(
                    .validatingManifest,
                    detail: "Validating the repaired widget plan before saving.",
                    to: progress
                )
                let manifest = try buildManifest(from: repaired, fallbackPrompt: prompt)
                return try await preflight(manifest, progress: progress)
            } catch let repairError as WidgetManifestGenerationError {
                Log.Widgets.error("Widget plan repair failed", error: repairError)
                throw repairError
            } catch {
                Log.Widgets.error("Widget plan repair request failed", error: error)
                throw error
            }
        }
    }

    private func requestPlan(
        messages: [ChatMessage],
        instructions: String,
        requestID: UUID
    ) async throws -> GeneratedWidgetPlan {
        do {
            if let completionProvider {
                return try await completionProvider(messages, instructions)
            }

            let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
            let response = try await contextService.generateWidgetPlan(
                requestID: requestID,
                prompt: prompt,
                instructions: instructions,
                transcriptRenderer: { response in
                    self.rawPlanDebugString(from: response)
                }
            )
            return response.value
        } catch {
            throw WidgetManifestGenerationError.llmFailed(error.localizedDescription)
        }
    }

    private func buildManifest(
        from response: GeneratedWidgetPlan,
        fallbackPrompt: String
    ) throws -> WidgetManifest {
        do {
            let manifest = try response.toManifest(fallbackPrompt: fallbackPrompt)
            return try WidgetManifestValidator.validate(manifest)
        } catch let error as WidgetManifestGenerationError {
            throw error
        } catch let error as WidgetPlanCompilationError {
            throw WidgetManifestGenerationError.validationFailed(error.localizedDescription)
        } catch let error as WidgetManifestValidationError {
            throw WidgetManifestGenerationError.validationFailed(error.localizedDescription)
        } catch {
            throw WidgetManifestGenerationError.parseFailed(error.localizedDescription)
        }
    }

    private func preflight(
        _ manifest: WidgetManifest,
        progress: WidgetManifestGenerationProgressHandler?
    ) async throws -> WidgetManifest {
        await report(
            .preflightingWidget,
            detail: "Running the widget once in a hidden dashboard runtime before saving.",
            to: progress
        )

        do {
            try await preflightProvider(manifest)
            return manifest
        } catch let error as WidgetManifestGenerationError {
            throw error
        } catch let error as WidgetManifestPreflightError {
            throw WidgetManifestGenerationError.preflightFailed(error.localizedDescription)
        } catch {
            throw WidgetManifestGenerationError.preflightFailed(error.localizedDescription)
        }
    }

    private func repairMessages(
        prompt: String,
        response: GeneratedWidgetPlan,
        failure: WidgetManifestGenerationError
    ) -> [ChatMessage] {
        let rawPlan = rawPlanDebugString(from: response)
        let repairPrompt = """
        The previous WidgetPlan was invalid. Repair it and return a single corrected WidgetPlan.

        Original user request:
        \(prompt)

        Compilation or validation error:
        \(failure.localizedDescription)

        Invalid plan:
        \(rawPlan)

        Keep the same intent, use only the allowed widget types, source kinds, and plan fields, and fill every required section exactly.
        If the failure mentions an HTTP status or a broken URL, do not reuse that URL. Choose a canonical public endpoint instead of inventing a site-specific API path.
        """

        return [
            .user(prompt),
            .assistant(rawPlan),
            .user(repairPrompt),
        ]
    }

    private func rawPlanDebugString(from response: GeneratedWidgetPlan) -> String {
        WheelStructuredJSONCodec.prettyPrintedString(from: response) ?? "<unavailable>"
    }

    private func report(
        _ phase: WidgetManifestGenerationProgress.Phase,
        detail: String,
        to progress: WidgetManifestGenerationProgressHandler?
    ) async {
        guard let progress else { return }
        await progress(.init(phase: phase, detail: detail))
    }
}

enum WidgetManifestGenerationError: LocalizedError, Equatable {
    case llmFailed(String)
    case parseFailed(String)
    case validationFailed(String)
    case preflightFailed(String)

    var errorDescription: String? {
        switch self {
        case .llmFailed(let detail):
            return "Widget generation failed: \(detail)"
        case .parseFailed(let detail):
            return "Failed to parse widget response: \(detail)"
        case .validationFailed(let detail):
            return "Generated widget plan is invalid: \(detail)"
        case .preflightFailed(let detail):
            return "Widget preflight failed: \(detail)"
        }
    }
}
