import Foundation

/// Generates module manifests by calling an LLM and validating the output.
/// Includes a repair loop: on validation failure, re-prompts with error message (max 2 retries).
final class ModuleGenerator {
    private let maxRepairAttempts = 2

    init() {}

    /// Generate a validated module manifest from a user description.
    func generate(prompt: String) async throws -> ModuleManifest {
        let systemPrompt = ModuleSystemPrompt.build()
        var messages = [ChatMessage.user(prompt)]
        var lastError: Error?

        for attempt in 0...maxRepairAttempts {
            let response: GeneratedModuleManifest
            do {
                response = try await OnDeviceLLM.shared.complete(
                    messages: messages,
                    instructions: systemPrompt,
                    generating: GeneratedModuleManifest.self
                )
            } catch {
                throw ModuleGenerationError.llmFailed(error.localizedDescription)
            }

            let manifest: ModuleManifest
            do {
                manifest = try response.toManifest()
            } catch {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(renderStructuredResponse(response)))
                    messages.append(.user(
                        "Your previous response had invalid structured values. Error: \(error.localizedDescription). " +
                        "Please correct the fields and return a valid manifest matching the schema."
                    ))
                    lastError = error
                    continue
                }
                throw ModuleGenerationError.parseFailed(
                    "Failed to decode structured manifest after \(attempt + 1) attempts: \(error.localizedDescription)"
                )
            }

            // Validate
            do {
                return try ModuleValidator.validate(manifest)
            } catch let validationError as ModuleValidationError {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(renderStructuredResponse(response)))
                    messages.append(.user(
                        "The module failed validation: \(validationError.localizedDescription). " +
                        "Please fix the issue and return the corrected structured manifest."
                    ))
                    lastError = validationError
                    continue
                }
                throw ModuleGenerationError.validationFailed(validationError.localizedDescription)
            }
        }

        throw ModuleGenerationError.exhaustedRetries(lastError?.localizedDescription ?? "unknown")
    }

    /// Edit an existing module manifest based on user instructions.
    func edit(
        currentManifest: ModuleManifest,
        editPrompt: String
    ) async throws -> ModuleManifest {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestJSON = String(data: try encoder.encode(currentManifest), encoding: .utf8) ?? "{}"

        let systemPrompt = ModuleSystemPrompt.buildForEdit(currentManifest: manifestJSON)
        var messages = [ChatMessage.user(editPrompt)]
        var lastError: Error?

        for attempt in 0...maxRepairAttempts {
            let response: GeneratedModuleManifest
            do {
                response = try await OnDeviceLLM.shared.complete(
                    messages: messages,
                    instructions: systemPrompt,
                    generating: GeneratedModuleManifest.self
                )
            } catch {
                throw ModuleGenerationError.llmFailed(error.localizedDescription)
            }

            let manifest: ModuleManifest
            do {
                manifest = try response.toManifest(preserving: currentManifest)
            } catch {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(renderStructuredResponse(response)))
                    messages.append(.user(
                        "Your previous response had invalid structured values. Error: \(error.localizedDescription). " +
                        "Please correct the fields and return a valid manifest matching the schema."
                    ))
                    lastError = error
                    continue
                }
                throw ModuleGenerationError.parseFailed(
                    "Failed to decode structured manifest after \(attempt + 1) attempts: \(error.localizedDescription)"
                )
            }

            do {
                return try ModuleValidator.validate(manifest)
            } catch let validationError as ModuleValidationError {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(renderStructuredResponse(response)))
                    messages.append(.user(
                        "The module failed validation: \(validationError.localizedDescription). " +
                        "Please fix the issue and return the corrected structured manifest."
                    ))
                    lastError = validationError
                    continue
                }
                throw ModuleGenerationError.validationFailed(validationError.localizedDescription)
            }
        }

        throw ModuleGenerationError.exhaustedRetries(lastError?.localizedDescription ?? "unknown")
    }

    private func renderStructuredResponse(_ response: GeneratedModuleManifest) -> String {
        GeneratedContentBridge.prettyJSONString(from: response) ?? response.name
    }
}

// MARK: - Errors

enum ModuleGenerationError: LocalizedError {
    case llmFailed(String)
    case parseFailed(String)
    case validationFailed(String)
    case exhaustedRetries(String)

    var errorDescription: String? {
        switch self {
        case .llmFailed(let detail):
            return "LLM request failed: \(detail)"
        case .parseFailed(let detail):
            return "Failed to parse module: \(detail)"
        case .validationFailed(let detail):
            return "Module validation failed: \(detail)"
        case .exhaustedRetries(let detail):
            return "Exhausted repair attempts. Last error: \(detail)"
        }
    }
}
