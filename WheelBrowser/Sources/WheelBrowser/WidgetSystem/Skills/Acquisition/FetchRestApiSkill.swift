import Foundation

/// Generic HTTPS GET skill with URL allowlist enforcement and SSRF prevention.
struct FetchRestApiSkill: WidgetSkill {
    let name = SkillName.fetchRestApi

    let paramSchema = """
    {
      "url": "string (required) — HTTPS URL to fetch. Must be from an allowed domain.",
      "headers": "object (optional) — additional HTTP headers",
      "json_path": "string (optional) — dot-separated path to extract from response, e.g. 'data.items'"
    }
    """

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

        if let headers = params["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

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

    private func extractPath(from root: Any, path: String) -> Any {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = root

        for component in components {
            if let dict = current as? [String: Any], let next = dict[component] {
                current = next
            } else if let array = current as? [Any], let index = Int(component), index < array.count {
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
