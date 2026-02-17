import Foundation

enum LettaError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case noAgentId

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Letta server URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noAgentId:
            return "No agent ID configured"
        }
    }
}

actor LettaClient {
    private let session: URLSession
    private var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    // MARK: - Agent Management

    func createAgent(
        name: String,
        description: String? = nil,
        systemPrompt: String? = nil,
        llmModel: String? = nil,
        llmEndpoint: String? = nil
    ) async throws -> LettaAgent {
        let url = baseURL.appendingPathComponent("v1/agents")

        // Create explicit LLM config with correct endpoint (must include /v1 for OpenAI-compatible)
        var llmConfig: LLMConfig? = nil
        if let model = llmModel, let endpoint = llmEndpoint {
            // Ensure endpoint ends with /v1 for OpenAI compatibility
            var correctedEndpoint = endpoint
            if !correctedEndpoint.hasSuffix("/v1") {
                correctedEndpoint = correctedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                correctedEndpoint += "/v1"
            }
            llmConfig = LLMConfig(
                model: model,
                modelEndpointType: "openai",
                modelEndpoint: correctedEndpoint,
                contextWindow: 8192
            )
        }

        let request = CreateAgentRequest(
            name: name,
            description: description,
            metadata: ["source": "wheel-browser"],
            system: systemPrompt,
            model: nil,
            embedding: nil,
            llmConfig: llmConfig,
            embeddingConfig: nil
        )

        return try await post(url: url, body: request)
    }

    func getAgent(id: String) async throws -> LettaAgent {
        let url = baseURL.appendingPathComponent("v1/agents/\(id)")
        return try await get(url: url)
    }

    func listAgents() async throws -> [LettaAgent] {
        let url = baseURL.appendingPathComponent("v1/agents")
        return try await get(url: url)
    }

    func deleteAgent(id: String) async throws {
        let url = baseURL.appendingPathComponent("v1/agents/\(id)")
        _ = try await delete(url: url)
    }

    // MARK: - Messaging

    func sendMessage(
        agentId: String,
        message: String,
        stream: Bool = false
    ) async throws -> [LettaResponseMessage] {
        let url = baseURL.appendingPathComponent("v1/agents/\(agentId)/messages")

        let request = SendMessageRequest(
            messages: [MessageInput(role: "user", content: message)],
            streamSteps: stream,
            streamTokens: stream
        )

        let response: LettaMessageResponse = try await post(url: url, body: request)
        return response.messages
    }

    func streamMessage(
        agentId: String,
        message: String
    ) -> AsyncThrowingStream<StreamingChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("v1/agents/\(agentId)/messages")

                    let requestBody = SendMessageRequest(
                        messages: [MessageInput(role: "user", content: message)],
                        streamSteps: true,
                        streamTokens: true
                    )

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONEncoder().encode(requestBody)

                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LettaError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw LettaError.httpError(httpResponse.statusCode, nil)
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }
                            if let data = jsonString.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(StreamingChunk.self, from: data) {
                                continuation.yield(chunk)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Archival Memory

    func addToArchival(agentId: String, content: String) async throws -> ArchivalMemoryEntry {
        let url = baseURL.appendingPathComponent("v1/agents/\(agentId)/archival")
        let request = AddArchivalMemoryRequest(text: content)
        return try await post(url: url, body: request)
    }

    func getArchivalMemory(agentId: String, limit: Int = 100) async throws -> [ArchivalMemoryEntry] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/agents/\(agentId)/archival"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = components?.url else {
            throw LettaError.invalidURL
        }

        return try await get(url: url)
    }

    // MARK: - Health Check

    func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("v1/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Private Helpers

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LettaError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw LettaError.httpError(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LettaError.decodingError(error)
        }
    }

    private func post<T: Decodable, B: Encodable>(url: URL, body: B) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LettaError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw LettaError.httpError(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LettaError.decodingError(error)
        }
    }

    private func delete(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LettaError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw LettaError.httpError(httpResponse.statusCode, message)
        }

        return data
    }
}
