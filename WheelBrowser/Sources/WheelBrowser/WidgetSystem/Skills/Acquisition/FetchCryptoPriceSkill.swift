import Foundation

/// Fetches cryptocurrency price data from the CoinGecko public API.
struct FetchCryptoPriceSkill: WidgetSkill {
    let name = SkillName.fetchCryptoPrice

    let paramSchema = """
    {
      "coin_id": "string (required) — CoinGecko coin ID, e.g. 'bitcoin', 'ethereum'",
      "vs_currency": "string (optional, default 'usd') — target currency",
      "days": "integer (optional, default 1) — price history days (1, 7, 30, 90, 365)",
      "_output_fields": "timestamp_ms (int), price (double), coin_id (string), vs_currency (string), volume (double, optional)"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        guard let coinId = params["coin_id"] as? String, !coinId.isEmpty else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.missing("coin_id"))
        }

        let vsCurrency = (params["vs_currency"] as? String) ?? "usd"
        let days: Int
        if let d = params["days"] as? Int {
            days = d
        } else if let d = params["days"] as? Double {
            days = Int(d)
        } else {
            days = 1
        }

        let urlString = "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart?vs_currency=\(vsCurrency)&days=\(days)"
        guard let url = URL(string: urlString) else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.invalid("coin_id", coinId))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.badStatus(code))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prices = json["prices"] as? [[Double]] else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.parseError)
        }

        let totalVolumes = json["total_volumes"] as? [[Double]] ?? []
        let volumeMap = Dictionary(totalVolumes.map { (Int($0[0]), $0[1]) }, uniquingKeysWith: { _, latest in latest })

        return prices.map { point -> [String: Any] in
            let timestampMs = Int(point[0])
            var result: [String: Any] = [
                "timestamp_ms": timestampMs,
                "price": point[1],
                "coin_id": coinId,
                "vs_currency": vsCurrency,
            ]
            if let volume = volumeMap[timestampMs] {
                result["volume"] = volume
            }
            return result
        }
    }
}
