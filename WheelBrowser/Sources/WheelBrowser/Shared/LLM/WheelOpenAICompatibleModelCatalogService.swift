import Foundation

enum WheelOpenAICompatibleModelCatalogError: LocalizedError, Equatable {
    case unsupportedProvider
    case missingBaseURL
    case invalidBaseURL
    case missingAPIKey
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The selected provider does not expose an OpenAI-compatible model catalog."
        case .missingBaseURL:
            return "Enter a Base URL to load models from the endpoint."
        case .invalidBaseURL:
            return "The configured Base URL is invalid."
        case .missingAPIKey:
            return "Save an API key to load models from the endpoint."
        case .invalidResponse:
            return "The endpoint returned an invalid model list."
        case .requestFailed(let message):
            return message
        }
    }
}

actor WheelOpenAICompatibleModelCatalogService {
    static let shared = WheelOpenAICompatibleModelCatalogService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchModelIDs(
        for providerID: WheelModelProviderID,
        baseURL: String,
        apiKey: String?
    ) async throws -> [String] {
        guard providerID.supportsEndpointModelCatalog else {
            throw WheelOpenAICompatibleModelCatalogError.unsupportedProvider
        }

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBaseURL.isEmpty == false else {
            throw WheelOpenAICompatibleModelCatalogError.missingBaseURL
        }

        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if providerID.requiresAPIKey, trimmedAPIKey?.isEmpty != false {
            throw WheelOpenAICompatibleModelCatalogError.missingAPIKey
        }

        var request = URLRequest(url: try Self.modelsURL(baseURLString: trimmedBaseURL))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let trimmedAPIKey, trimmedAPIKey.isEmpty == false {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WheelOpenAICompatibleModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.mapFailure(data: data, statusCode: httpResponse.statusCode)
        }

        let payload: ModelListResponse
        do {
            payload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        } catch {
            throw WheelOpenAICompatibleModelCatalogError.invalidResponse
        }

        var modelIDs: [String] = []
        var seenModelIDs = Set<String>()
        for model in payload.data {
            let trimmedModelID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedModelID.isEmpty == false else {
                continue
            }
            guard seenModelIDs.insert(trimmedModelID).inserted else {
                continue
            }
            modelIDs.append(trimmedModelID)
        }
        return modelIDs
    }

    // Mirror the runtime transport path resolution so settings probe the same endpoint shape.
    private static func modelsURL(baseURLString: String) throws -> URL {
        guard let baseURL = URL(string: baseURLString) else {
            throw WheelOpenAICompatibleModelCatalogError.invalidBaseURL
        }
        if baseURL.path.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("models")
        }
        return baseURL.appendingPathComponent("v1/models")
    }

    private static func mapFailure(data: Data, statusCode: Int) -> WheelOpenAICompatibleModelCatalogError {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           message.isEmpty == false {
            return .requestFailed(message)
        }

        let payload = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.isEmpty == false {
            return .requestFailed(payload)
        }

        return .requestFailed("The endpoint returned HTTP \(statusCode) while loading models.")
    }
}

private struct ModelListResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct ErrorEnvelope: Decodable {
    let error: ErrorPayload

    struct ErrorPayload: Decodable {
        let message: String?
    }
}
