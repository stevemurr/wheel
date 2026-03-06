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
            let response: String
            do {
                response = try await OnDeviceLLM.shared.complete(
                    messages: messages,
                    instructions: systemPrompt
                )
            } catch {
                throw ModuleGenerationError.llmFailed(error.localizedDescription)
            }

            // Parse JSON from response
            let manifest: ModuleManifest
            do {
                manifest = try parseManifest(from: response)
            } catch {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(response))
                    messages.append(.user(
                        "Your response was not valid JSON. Error: \(error.localizedDescription). " +
                        "Please output ONLY a valid JSON object."
                    ))
                    lastError = error
                    continue
                }
                throw ModuleGenerationError.parseFailed(
                    "Failed to parse manifest after \(attempt + 1) attempts: \(error.localizedDescription)"
                )
            }

            // Validate
            do {
                return try ModuleValidator.validate(manifest)
            } catch let validationError as ModuleValidationError {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(response))
                    messages.append(.user(
                        "The module failed validation: \(validationError.localizedDescription). " +
                        "Please fix the issue and output the corrected JSON."
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
            let response: String
            do {
                response = try await OnDeviceLLM.shared.complete(
                    messages: messages,
                    instructions: systemPrompt
                )
            } catch {
                throw ModuleGenerationError.llmFailed(error.localizedDescription)
            }

            let manifest: ModuleManifest
            do {
                var parsed = try parseManifest(from: response)
                // Preserve the original ID for edits
                parsed.id = currentManifest.id
                parsed.version = currentManifest.version + 1
                parsed.createdAt = currentManifest.createdAt
                parsed.updatedAt = Date()
                manifest = parsed
            } catch {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(response))
                    messages.append(.user(
                        "Your response was not valid JSON. Error: \(error.localizedDescription). " +
                        "Please output ONLY a valid JSON object."
                    ))
                    lastError = error
                    continue
                }
                throw ModuleGenerationError.parseFailed(
                    "Failed to parse manifest after \(attempt + 1) attempts: \(error.localizedDescription)"
                )
            }

            do {
                return try ModuleValidator.validate(manifest)
            } catch let validationError as ModuleValidationError {
                if attempt < maxRepairAttempts {
                    messages.append(.assistant(response))
                    messages.append(.user(
                        "The module failed validation: \(validationError.localizedDescription). " +
                        "Please fix the issue and output the corrected JSON."
                    ))
                    lastError = validationError
                    continue
                }
                throw ModuleGenerationError.validationFailed(validationError.localizedDescription)
            }
        }

        throw ModuleGenerationError.exhaustedRetries(lastError?.localizedDescription ?? "unknown")
    }

    // MARK: - JSON Parsing

    private func parseManifest(from response: String) throws -> ModuleManifest {
        // Strip markdown code fences if present
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            if let firstNewline = json.firstIndex(of: "\n") {
                json = String(json[json.index(after: firstNewline)...])
            }
            if json.hasSuffix("```") {
                json = String(json.dropLast(3))
            }
            json = json.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = json.data(using: .utf8) else {
            throw ModuleGenerationError.parseFailed("Response is not valid UTF-8")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ModuleManifest.self, from: data)
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
