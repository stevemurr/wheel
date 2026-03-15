import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct WheelTextGenerationOptions: Sendable {
    var maximumResponseTokens: Int?
    var temperature: Double?
    var deterministic: Bool

    init(
        maximumResponseTokens: Int? = nil,
        temperature: Double? = nil,
        deterministic: Bool = false
    ) {
        self.maximumResponseTokens = maximumResponseTokens
        self.temperature = temperature
        self.deterministic = deterministic
    }
}

enum WheelTextStreamChunk: Sendable {
    case reasoning(String)
    case partial(String)
    case completed(String)
}

protocol WheelLLMBackend: Sendable {
    var backendID: String { get }

    func availability(for endpoint: ModelEndpoint) async -> RuntimeAvailability

    func generateText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) async throws -> String

    func streamText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) -> AsyncThrowingStream<WheelTextStreamChunk, Error>
}

struct WheelOpenAICompatibleBackend: WheelLLMBackend {
    enum Kind: Sendable {
        case openAI
        case vllm
    }

    let backendID: String
    let kind: Kind
    let session: URLSession

    init(
        backendID: String,
        kind: Kind,
        session: URLSession = .shared
    ) {
        self.backendID = backendID
        self.kind = kind
        self.session = session
    }

    func availability(for endpoint: ModelEndpoint) async -> RuntimeAvailability {
        guard endpoint.options["baseURL"].flatMap(URL.init(string:)) != nil else {
            return RuntimeAvailability(
                status: .unavailable(reason: "Missing required base URL"),
                capabilities: capabilities
            )
        }
        if kind == .openAI,
           endpoint.options["apiKey"]?.isEmpty != false {
            return RuntimeAvailability(
                status: .unavailable(reason: "Missing required API key"),
                capabilities: capabilities
            )
        }

        return RuntimeAvailability(status: .available, capabilities: capabilities)
    }

    func generateText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) async throws -> String {
        let request = try makeChatRequest(
            endpoint: endpoint,
            instructions: instructions,
            history: history,
            prompt: prompt,
            options: options,
            stream: false
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeError.transportFailed("Invalid response")
        }
        if http.statusCode >= 400 {
            throw mapFailure(data: data, statusCode: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(WheelOpenAICompatibleCompletionResponse.self, from: data)
                .requireMessageContent()
        } catch let error as RuntimeError {
            throw error
        } catch {
            throw RuntimeError.transportFailed(error.localizedDescription)
        }
    }

    func streamText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) -> AsyncThrowingStream<WheelTextStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(
                        endpoint: endpoint,
                        instructions: instructions,
                        history: history,
                        prompt: prompt,
                        options: options,
                        stream: true
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw RuntimeError.transportFailed("Invalid response")
                    }
                    if http.statusCode >= 400 {
                        var mutableBytes = bytes
                        let data = try await collectData(from: &mutableBytes)
                        throw mapFailure(data: data, statusCode: http.statusCode)
                    }

                    var aggregate = ""
                    for try await payload in bytes.sseEvents {
                        let data = Data(payload.utf8)
                        if let errorEnvelope = try? JSONDecoder().decode(WheelOpenAICompatibleErrorEnvelope.self, from: data) {
                            throw mapFailure(errorEnvelope: errorEnvelope, statusCode: nil)
                        }
                        let chunk = try JSONDecoder().decode(WheelOpenAICompatibleStreamResponse.self, from: data)
                        if let runtimeError = chunk.runtimeError {
                            throw runtimeError
                        }
                        let reasoning = chunk.deltaReasoningText
                        if reasoning.isEmpty == false {
                            continuation.yield(.reasoning(reasoning))
                        }
                        let text = chunk.deltaText
                        if text.isEmpty == false {
                            aggregate.append(text)
                            continuation.yield(.partial(text))
                        }
                    }
                    continuation.yield(.completed(aggregate))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func makeChatRequest(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions,
        stream: Bool
    ) throws -> URLRequest {
        let url = try completionsURL(baseURLString: endpoint.options["baseURL"] ?? "")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = endpoint.options["apiKey"], apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if kind == .openAI,
           let organization = endpoint.options["organization"],
           organization.isEmpty == false {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }

        var body: [String: Any] = [
            "model": endpoint.modelID,
            "messages": makeMessages(
                instructions: instructions,
                history: history,
                prompt: prompt
            ),
            "stream": stream
        ]
        if let maximumResponseTokens = options.maximumResponseTokens {
            body["max_tokens"] = maximumResponseTokens
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        } else if options.deterministic {
            body["temperature"] = 0
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private var capabilities: RuntimeCapabilities {
        RuntimeCapabilities(
            supportsTextGeneration: true,
            supportsTextStreaming: true,
            supportsStructuredOutput: true,
            supportsExactTokenEstimation: false,
            supportsLocaleHints: false
        )
    }

    private func completionsURL(baseURLString: String) throws -> URL {
        guard let baseURL = URL(string: baseURLString) else {
            throw RuntimeError.unavailable("Invalid base URL")
        }
        if baseURL.path.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("chat/completions")
        }
        return baseURL.appendingPathComponent("v1/chat/completions")
    }

    private func makeMessages(
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        if let instructions, instructions.isEmpty == false {
            messages.append(["role": "system", "content": instructions])
        }
        messages.append(
            contentsOf: history.map {
                [
                    "role": $0.role.rawValue,
                    "content": $0.text
                ]
            }
        )
        messages.append(["role": "user", "content": prompt])
        return messages
    }

    private func mapFailure(data: Data, statusCode: Int) -> RuntimeError {
        if let envelope = try? JSONDecoder().decode(WheelOpenAICompatibleErrorEnvelope.self, from: data) {
            return mapFailure(errorEnvelope: envelope, statusCode: statusCode)
        }
        return mapFailure(
            message: String(decoding: data, as: UTF8.self),
            code: nil,
            type: nil,
            statusCode: statusCode
        )
    }

    private func mapFailure(
        errorEnvelope: WheelOpenAICompatibleErrorEnvelope,
        statusCode: Int?
    ) -> RuntimeError {
        mapFailure(
            message: errorEnvelope.error.message ?? "\(backendID) request failed",
            code: errorEnvelope.error.code,
            type: errorEnvelope.error.type,
            statusCode: statusCode
        )
    }

    private func mapFailure(
        message: String,
        code: String?,
        type: String?,
        statusCode: Int?
    ) -> RuntimeError {
        let lowered = [message, code, type]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if lowered.contains("context_length")
            || lowered.contains("maximum context length")
            || lowered.contains("context window")
            || lowered.contains("too many tokens") {
            return .contextOverflow(message)
        }

        if lowered.contains("content_filter")
            || lowered.contains("refusal")
            || lowered.contains("safety")
            || lowered.contains("policy") {
            return .refusal(message)
        }

        if let statusCode {
            return .transportFailed(message.isEmpty ? "HTTP \(statusCode)" : message)
        }
        return .transportFailed(message)
    }

    private func collectData(
        from bytes: inout URLSession.AsyncBytes
    ) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct WheelAppleBackend: WheelLLMBackend {
    let backendID: String = WheelModelProviderID.apple.rawValue

    func availability(for endpoint: ModelEndpoint) async -> RuntimeAvailability {
        do {
            let model = try makeModel(for: endpoint)
            return RuntimeAvailability(
                status: availabilityStatus(for: model.availability),
                capabilities: capabilities
            )
        } catch let error as RuntimeError {
            return RuntimeAvailability(
                status: .unavailable(reason: errorDescription(for: error)),
                capabilities: capabilities
            )
        } catch {
            return RuntimeAvailability(
                status: .unavailable(reason: error.localizedDescription),
                capabilities: capabilities
            )
        }
    }

    func generateText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) async throws -> String {
        let session = try makeSession(
            endpoint: endpoint,
            instructions: instructions,
            history: history
        )
        do {
            let response = try await session.respond(
                to: prompt,
                options: makeOptions(from: options)
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error)
        } catch {
            throw RuntimeError.generationFailed(error.localizedDescription)
        }
    }

    func streamText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) -> AsyncThrowingStream<WheelTextStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try makeSession(
                        endpoint: endpoint,
                        instructions: instructions,
                        history: history
                    )
                    let stream = session.streamResponse(
                        to: prompt,
                        options: makeOptions(from: options)
                    )
                    for try await snapshot in stream {
                        continuation.yield(.partial(snapshot.content))
                    }
                    let collected = try await stream.collect()
                    continuation.yield(.completed(collected.content))
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: map(error))
                } catch {
                    continuation.finish(throwing: RuntimeError.generationFailed(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private var capabilities: RuntimeCapabilities {
        RuntimeCapabilities(
            supportsTextGeneration: true,
            supportsTextStreaming: true,
            supportsStructuredOutput: true,
            supportsExactTokenEstimation: false,
            supportsLocaleHints: true
        )
    }

    private func makeSession(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn]
    ) throws -> LanguageModelSession {
        LanguageModelSession(
            model: try makeModel(for: endpoint),
            tools: [],
            instructions: buildInstructions(
                instructions: instructions,
                history: history
            )
        )
    }

    func buildInstructions(
        instructions: String?,
        history: [WheelConversationTurn]
    ) -> String? {
        var sections: [String] = []
        if let instructions, instructions.isEmpty == false {
            sections.append(instructions)
        }
        if history.isEmpty == false {
            let renderedHistory = history
                .map { "\($0.role.rawValue.capitalized): \($0.text)" }
                .joined(separator: "\n\n")
            sections.append(
                """
                Prior conversation:
                \(renderedHistory)
                """
            )
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func makeModel(for endpoint: ModelEndpoint) throws -> SystemLanguageModel {
        if let adapterName = endpoint.options["adapter"],
           adapterName.isEmpty == false,
           let adapter = try? SystemLanguageModel.Adapter(name: adapterName) {
            return SystemLanguageModel(
                adapter: adapter,
                guardrails: guardrails(for: endpoint)
            )
        }

        switch endpoint.modelID {
        case "default":
            return SystemLanguageModel.default
        case "general":
            return SystemLanguageModel(
                useCase: .general,
                guardrails: guardrails(for: endpoint)
            )
        case "contentTagging":
            return SystemLanguageModel(
                useCase: .contentTagging,
                guardrails: guardrails(for: endpoint)
            )
        default:
            throw RuntimeError.unavailable(
                "Unsupported Apple model ID \(endpoint.modelID). Supported values are default, general, and contentTagging."
            )
        }
    }

    private func guardrails(for endpoint: ModelEndpoint) -> SystemLanguageModel.Guardrails {
        switch endpoint.options["guardrails"] {
        case "permissiveContentTransformations":
            return .permissiveContentTransformations
        default:
            return .default
        }
    }

    private func availabilityStatus(
        for availability: SystemLanguageModel.Availability
    ) -> RuntimeAvailability.Status {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(reason: "Device not eligible for Foundation Models")
            case .appleIntelligenceNotEnabled:
                return .unavailable(reason: "Apple Intelligence is not enabled")
            case .modelNotReady:
                return .unavailable(reason: "Foundation Models assets are not ready")
            @unknown default:
                return .unavailable(reason: "Foundation Models is unavailable")
            }
        @unknown default:
            return .unavailable(reason: "Foundation Models is unavailable")
        }
    }

    private func makeOptions(from options: WheelTextGenerationOptions) -> GenerationOptions {
        if options.deterministic {
            return GenerationOptions(
                sampling: .greedy,
                temperature: options.temperature ?? 0,
                maximumResponseTokens: options.maximumResponseTokens
            )
        }
        return GenerationOptions(
            temperature: options.temperature,
            maximumResponseTokens: options.maximumResponseTokens
        )
    }

    private func map(_ error: LanguageModelSession.GenerationError) -> RuntimeError {
        switch error {
        case .exceededContextWindowSize(let context):
            return .contextOverflow(context.debugDescription)
        case .unsupportedLanguageOrLocale(let context):
            return .unsupportedLocale(context.debugDescription)
        case .refusal(let refusal, _):
            return .refusal(String(describing: refusal))
        case .unsupportedGuide(let context):
            return .unsupportedCapability(context.debugDescription)
        case .decodingFailure(let context):
            return .generationFailed(context.debugDescription)
        default:
            return .generationFailed(error.localizedDescription)
        }
    }

    private func errorDescription(for error: RuntimeError) -> String {
        switch error {
        case .unavailable(let value),
             .unsupportedCapability(let value),
             .unsupportedLocale(let value),
             .contextOverflow(let value),
             .refusal(let value),
             .generationFailed(let value),
             .transportFailed(let value):
            return value
        }
    }
}
#else
struct WheelAppleBackend: WheelLLMBackend {
    let backendID: String = WheelModelProviderID.apple.rawValue

    func buildInstructions(
        instructions: String?,
        history: [WheelConversationTurn]
    ) -> String? {
        var sections: [String] = []
        if let instructions, instructions.isEmpty == false {
            sections.append(instructions)
        }
        if history.isEmpty == false {
            let renderedHistory = history
                .map { "\($0.role.rawValue.capitalized): \($0.text)" }
                .joined(separator: "\n\n")
            sections.append(
                """
                Prior conversation:
                \(renderedHistory)
                """
            )
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    func availability(for endpoint: ModelEndpoint) async -> RuntimeAvailability {
        _ = endpoint
        return RuntimeAvailability(
            status: .unavailable(reason: "FoundationModels is unavailable"),
            capabilities: RuntimeCapabilities()
        )
    }

    func generateText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) async throws -> String {
        _ = endpoint
        _ = instructions
        _ = history
        _ = prompt
        _ = options
        throw RuntimeError.unavailable("FoundationModels is unavailable")
    }

    func streamText(
        endpoint: ModelEndpoint,
        instructions: String?,
        history: [WheelConversationTurn],
        prompt: String,
        options: WheelTextGenerationOptions
    ) -> AsyncThrowingStream<WheelTextStreamChunk, Error> {
        _ = endpoint
        _ = instructions
        _ = history
        _ = prompt
        _ = options
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: RuntimeError.unavailable("FoundationModels is unavailable"))
        }
    }
}
#endif

private struct WheelOpenAICompatibleErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable {
        let message: String?
        let type: String?
        let code: String?
    }

    let error: ErrorPayload
}

private struct WheelOpenAICompatibleCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: WheelOpenAICompatibleContentPayload
            let refusal: String?
        }

        let message: Message
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]

    func requireMessageContent() throws -> String {
        guard let choice = choices.first else {
            throw RuntimeError.generationFailed("Missing completion choice")
        }
        if let refusal = choice.message.refusal, refusal.isEmpty == false {
            throw RuntimeError.refusal(refusal)
        }
        if let refusal = choice.message.content.refusal, refusal.isEmpty == false {
            throw RuntimeError.refusal(refusal)
        }
        if choice.finishReason == "content_filter" {
            throw RuntimeError.refusal("The response was blocked by content filtering")
        }
        guard let content = choice.message.content.text else {
            throw RuntimeError.generationFailed("Missing completion content")
        }
        return content
    }
}

private struct WheelOpenAICompatibleStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let refusal: String?
            let reasoning: String?
            let reasoningContent: String?

            private enum CodingKeys: String, CodingKey {
                case content
                case refusal
                case reasoning
                case reasoningContent = "reasoning_content"
            }
        }

        let delta: Delta
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]

    var deltaText: String {
        choices.first?.delta.content ?? ""
    }

    var deltaReasoningText: String {
        let delta = choices.first?.delta
        return delta?.reasoningContent ?? delta?.reasoning ?? ""
    }

    var runtimeError: RuntimeError? {
        guard let choice = choices.first else {
            return nil
        }
        if let refusal = choice.delta.refusal, refusal.isEmpty == false {
            return .refusal(refusal)
        }
        if choice.finishReason == "content_filter" {
            return .refusal("The response was blocked by content filtering")
        }
        return nil
    }
}

private struct WheelOpenAICompatibleContentPayload: Decodable {
    struct Part: Decodable {
        let type: String?
        let text: String?
    }

    let text: String?
    let refusal: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
            refusal = nil
            return
        }
        if let parts = try? container.decode([Part].self) {
            let textual = parts
                .filter { $0.type != "refusal" }
                .compactMap(\.text)
                .joined()
            let refusalText = parts
                .filter { $0.type == "refusal" }
                .compactMap(\.text)
                .joined()
            text = textual.isEmpty ? nil : textual
            refusal = refusalText.isEmpty ? nil : refusalText
            return
        }
        text = nil
        refusal = nil
    }
}
