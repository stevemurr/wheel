import Foundation

/// Generic HTTPS GET skill with URL allowlist enforcement and SSRF prevention.
struct FetchRestApiSkill: WidgetSkill {
    let name = SkillName.fetchRestApi

    var paramSchema: String {
        let domains = Self.allowedDomains.sorted().joined(separator: ", ")
        return """
        {
          "url": "string (required) — HTTPS URL to fetch. Allowed domains: \(domains)",
          "headers": "object (optional) — additional HTTP headers as {\"Header-Name\": \"value\"}",
          "json_path": "string (optional) — dot-separated path to extract from response, e.g. 'data.items'",
          "_output_note": "Output depends on the API endpoint. Use json_path to extract the relevant array. Output is always wrapped in an array."
        }
        """
    }

    /// Domains allowed for fetch_rest_api requests.
    static let allowedDomains: Set<String> = [
        "api.github.com",
        "api.coingecko.com",
        "hacker-news.firebaseio.com",
        "newsapi.org",
        "api.openweathermap.org",
        "jsonplaceholder.typicode.com",
        "api.exchangerate-api.com",
        "api.spacexdata.com",
        "pokeapi.co",
        "swapi.dev",
    ]

    func execute(params: [String: Any]) async throws -> Any {
        guard let urlString = params["url"] as? String, !urlString.isEmpty else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.missing("url"))
        }

        guard let url = URL(string: urlString) else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.invalid("url", urlString))
        }

        // SSRF prevention: only HTTPS, only allowed domains
        guard url.scheme == "https" else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.invalid("url", "Only HTTPS URLs are allowed"))
        }

        guard let host = url.host, Self.allowedDomains.contains(host) else {
            throw WidgetError.executionFailed(
                stepId: "",
                underlying: SkillParamError.invalid("url", "Domain '\(url.host ?? "")' is not in the allowlist")
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        // Only allow safe, non-sensitive headers to prevent credential injection
        let blockedHeaders: Set<String> = [
            "host", "authorization", "cookie", "proxy-authorization",
            "set-cookie", "transfer-encoding", "content-length",
        ]
        if let headers = params["headers"] as? [String: String] {
            for (key, value) in headers {
                guard !blockedHeaders.contains(key.lowercased()) else {
                    continue
                }
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Use a session configuration that does not follow redirects to prevent
        // SSRF via open redirects on allowed domains.
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.badStatus(code))
        }

        let parsed = try JSONSerialization.jsonObject(with: data)

        // Apply json_path extraction if specified
        if let jsonPath = params["json_path"] as? String, !jsonPath.isEmpty {
            return extractPath(from: parsed, path: jsonPath)
        }

        // Wrap non-array results in an array
        if let array = parsed as? [Any] {
            return array
        }
        return [parsed]
    }

    /// Validates that a resolved (non-template) URL is allowed at runtime.
    /// This re-checks domain allowlist for URLs that were template references at validation time.
    static func validateResolvedURL(_ urlString: String) throws {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              let host = url.host,
              allowedDomains.contains(host) else {
            throw SkillParamError.invalid("url", "Resolved URL '\(urlString)' is not allowed")
        }
    }

    private func extractPath(from root: Any, path: String) -> Any {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = root

        for component in components {
            if let dict = current as? [String: Any], let next = dict[component] {
                current = next
            } else if let array = current as? [Any], let index = Int(component), index >= 0, index < array.count {
                current = array[index]
            } else {
                return current
            }
        }

        if let array = current as? [Any] {
            return array
        }
        return [current]
    }
}

// MARK: - Redirect Prevention

/// URLSession delegate that blocks all redirects to prevent SSRF via open redirects.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Block all redirects — return nil to stop following the redirect
        completionHandler(nil)
    }
}
