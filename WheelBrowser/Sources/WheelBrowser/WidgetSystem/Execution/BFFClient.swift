import Foundation

/// Proxy client for routing skill execution through a Backend-For-Frontend server.
/// Falls back to direct HTTP when BFF is not configured.
actor BFFClient {
    private let baseURL: URL?
    private let session: URLSession

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    /// Whether the BFF is configured and available.
    var isConfigured: Bool {
        baseURL != nil
    }

    /// Route a skill execution through the BFF proxy.
    /// - Parameters:
    ///   - skillName: The skill to execute
    ///   - params: The skill parameters
    /// - Returns: The skill output
    func proxy(skillName: SkillName, params: [String: Any]) async throws -> Any {
        guard let baseURL else {
            throw BFFError.notConfigured
        }

        let url = baseURL.appendingPathComponent("proxy/\(skillName.rawValue)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = try JSONSerialization.data(withJSONObject: params)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BFFError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw BFFError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try JSONSerialization.jsonObject(with: data)
    }
}

enum BFFError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "BFF proxy not configured"
        case .invalidResponse:
            return "Invalid response from BFF proxy"
        case .httpError(let code, let message):
            return "BFF proxy HTTP \(code): \(message)"
        }
    }
}
