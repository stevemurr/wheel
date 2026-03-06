import Foundation

/// Generates widget pipeline specs by calling an LLM and validating the output.
/// Includes a repair loop when structured output still violates domain validation rules.
final class WidgetSpecGenerator {
    typealias CompletionProvider = @Sendable ([ChatMessage], String) async throws -> GeneratedWidgetPipelineSpec

    private let registry: SkillRegistry
    private let maxRepairAttempts = 2
    private let completionProvider: CompletionProvider

    init(registry: SkillRegistry) {
        self.registry = registry
        self.completionProvider = { messages, instructions in
            try await OnDeviceLLM.shared.complete(
                messages: messages,
                instructions: instructions,
                generating: GeneratedWidgetPipelineSpec.self
            )
        }
    }

    /// Test initializer that accepts a custom completion provider.
    init(registry: SkillRegistry, completionProvider: @escaping CompletionProvider) {
        self.registry = registry
        self.completionProvider = completionProvider
    }

    /// Generate a validated pipeline spec from a user description.
    func generate(prompt: String) async throws -> ValidatedSpec {
        let systemPrompt = SystemPromptBuilder.build(registry: registry)

        var messages = [ChatMessage.user(prompt)]
        var lastError: Error?

        for attempt in 0...maxRepairAttempts {
            let response: GeneratedWidgetPipelineSpec
            do {
                response = try await completionProvider(messages, systemPrompt)
            } catch {
                throw WidgetError.specGenerationFailed("LLM request failed: \(error.localizedDescription)")
            }

            let spec: WidgetPipelineSpec
            do {
                spec = try response.toWidgetPipelineSpec()
            } catch {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(renderStructuredResponse(response)))
                    messages.append(.user("Your previous response had invalid structured values. Error: \(error.localizedDescription). Please correct the fields and return a valid spec matching the schema."))
                    lastError = error
                    continue
                }
                throw WidgetError.specGenerationFailed("Failed to decode structured spec after \(attempt + 1) attempts: \(error.localizedDescription)")
            }

            // Validate
            do {
                return try SpecValidator.validate(spec)
            } catch let validationError as SpecValidationError {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(renderStructuredResponse(response)))
                    messages.append(.user("The spec failed validation: \(validationError.localizedDescription). Please fix the issue and return the corrected structured spec."))
                    lastError = validationError
                    continue
                }
                throw WidgetError.validationFailed(validationError)
            }
        }

        throw WidgetError.specGenerationFailed("Exhausted repair attempts. Last error: \(lastError?.localizedDescription ?? "unknown")")
    }

    private func renderStructuredResponse(_ response: GeneratedWidgetPipelineSpec) -> String {
        GeneratedContentBridge.prettyJSONString(from: response) ?? response.title
    }
}
