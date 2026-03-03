import Foundation

/// Fetches weather data from the OpenWeatherMap API.
struct FetchWeatherSkill: WidgetSkill {
    let name = SkillName.fetchWeather

    let paramSchema = """
    {
      "city": "string (required) — city name, e.g. 'London', 'New York'",
      "units": "string (optional, default 'metric') — one of: metric, imperial, standard",
      "api_key": "string (optional) — OpenWeatherMap API key. Uses built-in key if omitted."
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        guard let city = params["city"] as? String, !city.isEmpty else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.missing("city"))
        }

        let units = (params["units"] as? String) ?? "metric"
        let apiKey = (params["api_key"] as? String) ?? ""

        guard !apiKey.isEmpty else {
            // Return a stub response when no API key is configured
            return [[
                "city": city,
                "temp": 0,
                "feels_like": 0,
                "humidity": 0,
                "description": "API key required",
                "icon": "01d",
                "wind_speed": 0,
                "units": units,
            ] as [String: Any]]
        }

        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlString = "https://api.openweathermap.org/data/2.5/weather?q=\(encoded)&units=\(units)&appid=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.invalid("city", city))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.badStatus(code))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.parseError)
        }

        let main = json["main"] as? [String: Any] ?? [:]
        let weather = (json["weather"] as? [[String: Any]])?.first ?? [:]
        let wind = json["wind"] as? [String: Any] ?? [:]

        return [[
            "city": city,
            "temp": main["temp"] as? Double ?? 0,
            "feels_like": main["feels_like"] as? Double ?? 0,
            "humidity": main["humidity"] as? Int ?? 0,
            "description": weather["description"] as? String ?? "",
            "icon": weather["icon"] as? String ?? "",
            "wind_speed": wind["speed"] as? Double ?? 0,
            "units": units,
        ] as [String: Any]]
    }
}
