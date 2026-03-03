import Foundation

/// Generates widget pipeline specs by calling an LLM and validating the output.
/// Includes a repair loop: on validation failure, re-prompts with error message (max 2 retries).
final class WidgetSpecGenerator {
    private let llmClient: any LLMClient
    private let registry: SkillRegistry
    private let maxRepairAttempts = 2
    private let jsonDecoder = JSONDecoder()

    init(llmClient: any LLMClient, registry: SkillRegistry) {
        self.llmClient = llmClient
        self.registry = registry
    }

    /// Generate a validated pipeline spec from a user description.
    func generate(prompt: String, model: String) async throws -> ValidatedSpec {
        let systemPrompt = SystemPromptBuilder.build(registry: registry)

        var messages = [ChatMessage.user(prompt)]
        var lastError: Error?

        for attempt in 0...maxRepairAttempts {
            let options = LLMRequestOptions.widgetGeneration(model: model)

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
                    messages.append(.user("""
                    The spec failed validation: \(validationError.localizedDescription)

                    Please carefully review the ENTIRE spec for any other issues as well, then output the fully corrected JSON. \
                    Make sure all required parameters are present for each skill, all references point to preceding steps, \
                    and the last step is a render skill. Output ONLY the JSON object.
                    """))
                    lastError = validationError
                    continue
                }
                throw WidgetError.validationFailed(validationError)
            }
        }

        throw WidgetError.specGenerationFailed("Exhausted repair attempts. Last error: \(lastError?.localizedDescription ?? "unknown")")
    }

    private func parseSpec(from response: String) throws -> WidgetPipelineSpec {
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract content from markdown code fences anywhere in the response
        if let fenceStart = json.range(of: "```json"),
           let contentStart = json.range(of: "\n", range: fenceStart.upperBound..<json.endIndex) {
            let afterFence = json[contentStart.upperBound...]
            if let fenceEnd = afterFence.range(of: "```") {
                json = String(afterFence[afterFence.startIndex..<fenceEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let fenceStart = json.range(of: "```"),
                  let contentStart = json.range(of: "\n", range: fenceStart.upperBound..<json.endIndex) {
            let afterFence = json[contentStart.upperBound...]
            if let fenceEnd = afterFence.range(of: "```") {
                json = String(afterFence[afterFence.startIndex..<fenceEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Fallback: extract first top-level JSON object using brace matching
        if !json.hasPrefix("{"), let braceStart = json.firstIndex(of: "{") {
            var depth = 0
            var braceEnd: String.Index?
            var inString = false
            var escape = false
            for i in json.indices[braceStart...] {
                let c = json[i]
                if escape { escape = false; continue }
                if c == "\\" && inString { escape = true; continue }
                if c == "\"" { inString = !inString; continue }
                if inString { continue }
                if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { braceEnd = i; break } }
            }
            if let braceEnd {
                json = String(json[braceStart...braceEnd])
            }
        }

        guard let data = json.data(using: .utf8) else {
            throw WidgetError.specGenerationFailed("Response is not valid UTF-8")
        }

        return try jsonDecoder.decode(WidgetPipelineSpec.self, from: data)
    }
}
