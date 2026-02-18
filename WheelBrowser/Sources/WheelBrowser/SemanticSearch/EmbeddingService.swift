import Foundation
import NaturalLanguage

// MARK: - Protocol

/// Protocol for embedding services
protocol EmbeddingService: Sendable {
    /// The dimension of embeddings produced by this service
    var dimensions: Int { get }

    /// Generate an embedding for a single text
    func embed(text: String) async throws -> [Float]

    /// Generate embeddings for multiple texts (batched for efficiency)
    func embed(texts: [String]) async throws -> [[Float]]
}

// MARK: - API-based Embedding Service

/// Embedding service that calls an external API
actor APIEmbeddingService: EmbeddingService {
    let dimensions: Int
    private let endpoint: URL
    private let apiKey: String?
    private let modelName: String
    private let session: URLSession

    init(
        endpoint: URL,
        apiKey: String? = nil,
        modelName: String = "text-embedding-3-small",
        dimensions: Int = 1536
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.dimensions = dimensions
        self.session = URLSession.shared
    }

    func embed(text: String) async throws -> [Float] {
        let results = try await embed(texts: [text])
        guard let first = results.first else {
            throw EmbeddingError.emptyResponse
        }
        return first
    }

    func embed(texts: [String]) async throws -> [[Float]] {
        // Batch into chunks of 32 to avoid overloading the API
        let batchSize = 32
        var allEmbeddings: [[Float]] = []

        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])

            let embeddings = try await embedBatch(batch)
            allEmbeddings.append(contentsOf: embeddings)
        }

        return allEmbeddings
    }

    private func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = EmbeddingRequest(
            model: modelName,
            input: texts,
            dimensions: dimensions
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Embedding API error from \(endpoint): \(httpResponse.statusCode) - \(errorBody)")
            throw EmbeddingError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return result.data.sorted { $0.index < $1.index }.map { $0.embedding }
    }
}

// MARK: - Local NLEmbedding Service (fallback)

/// Embedding service using macOS NaturalLanguage framework
actor LocalEmbeddingService: EmbeddingService {
    let dimensions: Int = 512
    private let embedding: NLEmbedding?

    init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    var isAvailable: Bool {
        embedding != nil
    }

    func embed(text: String) async throws -> [Float] {
        guard let embedding = embedding else {
            throw EmbeddingError.serviceUnavailable("NLEmbedding.sentenceEmbedding not available")
        }

        // Truncate to reasonable length
        let truncated = String(text.prefix(5000))

        guard let vector = embedding.vector(for: truncated) else {
            throw EmbeddingError.embeddingFailed("Failed to generate embedding for text")
        }

        return vector.map { Float($0) }
    }

    func embed(texts: [String]) async throws -> [[Float]] {
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let embedding = try await self.embed(text: text)
                    return (index, embedding)
                }
            }

            var results: [(Int, [Float])] = []
            for try await result in group {
                results.append(result)
            }

            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}

// MARK: - Request/Response Types

private struct EmbeddingRequest: Encodable {
    let model: String
    let input: [String]
    let dimensions: Int?

    init(model: String, input: [String], dimensions: Int?) {
        self.model = model
        self.input = input
        // Only include dimensions for models that support it
        self.dimensions = model.contains("text-embedding-3") ? dimensions : nil
    }
}

private struct EmbeddingResponse: Decodable {
    let data: [EmbeddingData]

    struct EmbeddingData: Decodable {
        let index: Int
        let embedding: [Float]
    }
}

// MARK: - Errors

enum EmbeddingError: Error, LocalizedError {
    case serviceUnavailable(String)
    case embeddingFailed(String)
    case emptyResponse
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable(let msg): return "Embedding service unavailable: \(msg)"
        case .embeddingFailed(let msg): return "Embedding failed: \(msg)"
        case .emptyResponse: return "Empty response from embedding service"
        case .invalidResponse: return "Invalid response from embedding service"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        }
    }
}

// MARK: - Embedding Provider Enum

/// Supported embedding providers
enum EmbeddingProvider: String, CaseIterable {
    case openAI = "openai"
    case voyageAI = "voyage"
    case local = "local"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .voyageAI: return "Voyage AI"
        case .local: return "Local (macOS)"
        case .custom: return "Custom"
        }
    }
}
