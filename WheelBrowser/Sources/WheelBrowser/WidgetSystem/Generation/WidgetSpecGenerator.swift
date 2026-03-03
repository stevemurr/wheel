import Foundation

/// Generates widget pipeline specs by calling an LLM and validating the output.
/// Includes a repair loop: on validation failure, re-prompts with error message (max 2 retries).
final class WidgetSpecGenerator {
    private let llmClient: any LLMClient
    private let registry: SkillRegistry
    private let maxRepairAttempts = 2

    init(llmClient: any LLMClient, registry: SkillRegistry) {
        self.llmClient = llmClient
        self.registry = registry
    }

    /// Generate a validated pipeline spec from a user description.
    func generate(prompt: String) async throws -> ValidatedSpec {
        let systemPrompt = SystemPromptBuilder.build(registry: registry)

        var messages = [ChatMessage.user(prompt)]
        var lastError: Error?

        for attempt in 0...maxRepairAttempts {
            let options = LLMRequestOptions(temperature: 0.0, maxTokens: 2048)

            let response: String
            do {
                response = try await llmClient.complete(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    options: options
                )
            } catch {
                throw WidgetError.specGenerationFailed("LLM request failed: \(error.localizedDescription)")
            }

            // Parse JSON from response
            let spec: WidgetPipelineSpec
            do {
                spec = try parseSpec(from: response)
            } catch {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(response))
                    messages.append(.user("Your response was not valid JSON. Error: \(error.localizedDescription). Please output ONLY a valid JSON object."))
                    lastError = error
                    continue
                }
                throw WidgetError.specGenerationFailed("Failed to parse spec after \(attempt + 1) attempts: \(error.localizedDescription)")
            }

            // Validate
            do {
                return try SpecValidator.validate(spec)
            } catch let validationError as SpecValidationError {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(response))
                    messages.append(.user("The spec failed validation: \(validationError.localizedDescription). Please fix the issue and output the corrected JSON."))
                    lastError = validationError
                    continue
                }
                throw WidgetError.validationFailed(validationError)
            }
        }

        throw WidgetError.specGenerationFailed("Exhausted repair attempts. Last error: \(lastError?.localizedDescription ?? "unknown")")
    }

    private func parseSpec(from response: String) throws -> WidgetPipelineSpec {
        // Strip markdown code fences if present
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            // Remove opening fence (with optional language tag)
            if let firstNewline = json.firstIndex(of: "\n") {
                json = String(json[json.index(after: firstNewline)...])
            }
            // Remove closing fence
            if json.hasSuffix("```") {
                json = String(json.dropLast(3))
            }
            json = json.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = json.data(using: .utf8) else {
            throw WidgetError.specGenerationFailed("Response is not valid UTF-8")
        }

        return try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)
    }
}
