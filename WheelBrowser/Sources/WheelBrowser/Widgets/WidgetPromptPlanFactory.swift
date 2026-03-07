import Foundation

enum WidgetPromptPlanFactory {
    static func plan(for prompt: String) -> GeneratedWidgetPlan? {
        if let intent = HackerNewsPromptIntent(prompt: prompt) {
            return intent.plan
        }
        if let intent = CryptoPromptIntent(prompt: prompt) {
            return intent.plan
        }
        if let intent = FXPromptIntent(prompt: prompt) {
            return intent.plan
        }
        return nil
    }
}

private struct HackerNewsPromptIntent {
    let prompt: String
    let limit: Int

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = Self.normalize(trimmedPrompt)

        guard Self.referencesHackerNews(in: normalizedPrompt) else { return nil }
        guard Self.containsStoryIntent(in: normalizedPrompt) else { return nil }

        self.prompt = trimmedPrompt
        self.limit = Self.extractLimit(from: normalizedPrompt) ?? 5
    }

    var plan: GeneratedWidgetPlan {
        GeneratedWidgetPlan(
            title: limit == 1 ? "Hacker News Story" : "Top \(limit) Hacker News Stories",
            widgetType: "list",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: Self.algoliaFrontPageURL(limit: limit),
                jsonPath: "hits",
                resultShape: "collection",
                sortBy: nil,
                sortAscending: nil,
                limit: nil,
                timeZones: nil
            ),
            refreshSeconds: 900,
            prompt: prompt,
            text: nil,
            metric: nil,
            list: GeneratedWidgetListPlan(
                variant: "feed",
                labelField: "title",
                valueField: "points",
                subtitleField: "author",
                badgeField: nil,
                captionField: nil,
                iconField: nil,
                linkField: "url",
                maxItems: limit
            ),
            table: nil,
            chart: nil
        )
    }

    private static func algoliaFrontPageURL(limit: Int) -> String {
        var components = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "front_page"),
            URLQueryItem(name: "hitsPerPage", value: "\(max(1, min(limit, 20)))"),
        ]
        return components.url!.absoluteString
    }

    private static func referencesHackerNews(in prompt: String) -> Bool {
        prompt.contains("hacker news")
            || prompt.contains("hackernews")
            || containsWord("hn", in: prompt)
    }

    private static func containsStoryIntent(in prompt: String) -> Bool {
        prompt.contains("front page")
            || containsWord("headline", in: prompt)
            || containsWord("headlines", in: prompt)
            || containsWord("story", in: prompt)
            || containsWord("stories", in: prompt)
            || containsWord("article", in: prompt)
            || containsWord("articles", in: prompt)
            || containsWord("post", in: prompt)
            || containsWord("posts", in: prompt)
            || containsWord("top", in: prompt)
            || containsWord("best", in: prompt)
    }

    private static func extractLimit(from prompt: String) -> Int? {
        guard let match = prompt.range(of: #"\b([1-9]|1[0-9]|20)\b"#, options: .regularExpression),
              let value = Int(prompt[match]) else {
            return nil
        }
        return value
    }

    private static func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt == word
            || prompt.hasPrefix("\(word) ")
            || prompt.hasSuffix(" \(word)")
            || prompt.contains(" \(word) ")
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: #"[^a-z0-9 ]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CryptoPromptIntent {
    struct Asset: Hashable {
        let id: String
        let name: String
        let symbol: String
        let aliases: [String]
    }

    let prompt: String
    let assets: [Asset]

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = Self.normalize(trimmedPrompt)
        let assets = Self.deduplicate(Self.catalog.filter { asset in
            asset.aliases.contains { alias in
                Self.contains(alias: alias, in: normalizedPrompt)
            }
        })

        guard !assets.isEmpty else { return nil }
        guard Self.containsFinanceIntent(in: normalizedPrompt) else { return nil }

        self.prompt = trimmedPrompt
        self.assets = assets
    }

    var plan: GeneratedWidgetPlan {
        if assets.count == 1 {
            let asset = assets[0]
            return GeneratedWidgetPlan(
                title: "\(asset.name) Price",
                widgetType: "priceCard",
                source: GeneratedWidgetSourcePlan(
                    kind: "jsonAPI",
                    url: Self.coinGeckoMarketsURL(ids: [asset.id]),
                    jsonPath: nil,
                    resultShape: "collection",
                    sortBy: nil,
                    sortAscending: nil,
                    limit: 1,
                    timeZones: nil
                ),
                refreshSeconds: 300,
                prompt: prompt,
                text: nil,
                metric: GeneratedWidgetMetricPlan(
                    valueField: "current_price",
                    changeField: "price_change_24h",
                    changePercentField: "price_change_percentage_24h",
                    changeIsPercent: nil,
                    prefix: "$",
                    suffix: nil,
                    footnote: "24h change"
                ),
                list: nil,
                table: nil,
                chart: nil
            )
        }

        return GeneratedWidgetPlan(
            title: watchlistTitle(for: assets),
            widgetType: "list",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: Self.coinGeckoMarketsURL(ids: assets.map(\.id)),
                jsonPath: nil,
                resultShape: "collection",
                sortBy: "market_cap_rank",
                sortAscending: true,
                limit: assets.count,
                timeZones: nil
            ),
            refreshSeconds: 300,
            prompt: prompt,
            text: nil,
            metric: nil,
            list: GeneratedWidgetListPlan(
                variant: "compact",
                labelField: "name",
                valueField: "current_price",
                subtitleField: "symbol",
                badgeField: "market_cap_rank",
                captionField: nil,
                iconField: nil,
                linkField: nil,
                maxItems: assets.count
            ),
            table: nil,
            chart: nil
        )
    }

    private func watchlistTitle(for assets: [Asset]) -> String {
        let labels = assets.map(\.symbol)
        if labels.count <= 3 {
            return "\(labels.joined(separator: " • ")) Watchlist"
        }
        return "Crypto Watchlist"
    }

    private static func containsFinanceIntent(in prompt: String) -> Bool {
        containsWord("price", in: prompt)
            || containsWord("prices", in: prompt)
            || containsWord("watchlist", in: prompt)
            || containsWord("track", in: prompt)
            || containsWord("quote", in: prompt)
            || containsWord("quotes", in: prompt)
            || containsWord("crypto", in: prompt)
            || containsWord("coin", in: prompt)
            || containsWord("coins", in: prompt)
            || containsWord("token", in: prompt)
            || containsWord("tokens", in: prompt)
    }

    private static func coinGeckoMarketsURL(ids: [String]) -> String {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "\(max(ids.count, 1))"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "false"),
            URLQueryItem(name: "price_change_percentage", value: "24h"),
        ]
        return components.url!.absoluteString
    }

    private static func contains(alias: String, in prompt: String) -> Bool {
        let normalizedAlias = normalize(alias)
        if normalizedAlias.contains(" ") {
            return prompt.contains(normalizedAlias)
        }
        return containsWord(normalizedAlias, in: prompt)
    }

    private static func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt == word
            || prompt.hasPrefix("\(word) ")
            || prompt.hasSuffix(" \(word)")
            || prompt.contains(" \(word) ")
    }

    private static func deduplicate(_ assets: [Asset]) -> [Asset] {
        var seen = Set<Asset>()
        var result: [Asset] = []
        for asset in assets where seen.insert(asset).inserted {
            result.append(asset)
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: #"[^a-z0-9 ]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let catalog: [Asset] = [
        Asset(id: "bitcoin", name: "Bitcoin", symbol: "BTC", aliases: ["bitcoin", "btc"]),
        Asset(id: "ethereum", name: "Ethereum", symbol: "ETH", aliases: ["ethereum", "eth"]),
        Asset(id: "solana", name: "Solana", symbol: "SOL", aliases: ["solana", "sol"]),
        Asset(id: "ripple", name: "XRP", symbol: "XRP", aliases: ["xrp", "ripple"]),
        Asset(id: "cardano", name: "Cardano", symbol: "ADA", aliases: ["cardano", "ada"]),
        Asset(id: "dogecoin", name: "Dogecoin", symbol: "DOGE", aliases: ["dogecoin", "doge"]),
    ]
}

private struct FXPromptIntent {
    struct Currency: Hashable {
        let code: String
        let aliases: [String]
    }

    let prompt: String
    let base: Currency
    let quote: Currency

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = Self.normalize(trimmedPrompt)
        guard !normalizedPrompt.contains(where: \.isNumber) else { return nil }

        let matches = Self.deduplicate(Self.catalog.filter { currency in
            currency.aliases.contains { alias in
                Self.contains(alias: alias, in: normalizedPrompt)
            }
        })

        guard matches.count == 2 else { return nil }
        guard Self.containsFXIntent(in: normalizedPrompt) else { return nil }

        self.prompt = trimmedPrompt
        self.base = matches[0]
        self.quote = matches[1]
    }

    var plan: GeneratedWidgetPlan {
        GeneratedWidgetPlan(
            title: "\(base.code) to \(quote.code)",
            widgetType: "statCard",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: Self.frankfurterURL(base: base.code, quote: quote.code),
                jsonPath: nil,
                resultShape: "single",
                sortBy: nil,
                sortAscending: nil,
                limit: nil,
                timeZones: nil
            ),
            refreshSeconds: 1800,
            prompt: prompt,
            text: nil,
            metric: GeneratedWidgetMetricPlan(
                valueField: "rates.\(quote.code)",
                changeField: nil,
                changePercentField: nil,
                changeIsPercent: nil,
                prefix: nil,
                suffix: " \(quote.code)",
                footnote: nil
            ),
            list: nil,
            table: nil,
            chart: nil
        )
    }

    private static func frankfurterURL(base: String, quote: String) -> String {
        var components = URLComponents(string: "https://api.frankfurter.app/latest")!
        components.queryItems = [
            URLQueryItem(name: "from", value: base),
            URLQueryItem(name: "to", value: quote),
        ]
        return components.url!.absoluteString
    }

    private static func containsFXIntent(in prompt: String) -> Bool {
        containsWord("exchange", in: prompt)
            || containsWord("rate", in: prompt)
            || containsWord("fx", in: prompt)
            || containsWord("forex", in: prompt)
            || containsWord("currency", in: prompt)
            || prompt.contains(" to ")
            || prompt.contains(" against ")
    }

    private static func contains(alias: String, in prompt: String) -> Bool {
        let normalizedAlias = normalize(alias)
        return containsWord(normalizedAlias, in: prompt)
    }

    private static func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt == word
            || prompt.hasPrefix("\(word) ")
            || prompt.hasSuffix(" \(word)")
            || prompt.contains(" \(word) ")
    }

    private static func deduplicate(_ currencies: [Currency]) -> [Currency] {
        var seen = Set<Currency>()
        var result: [Currency] = []
        for currency in currencies where seen.insert(currency).inserted {
            result.append(currency)
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: #"[^a-z0-9 ]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let catalog: [Currency] = [
        Currency(code: "USD", aliases: ["usd", "dollar", "dollars", "us dollar", "us dollars"]),
        Currency(code: "EUR", aliases: ["eur", "euro", "euros"]),
        Currency(code: "GBP", aliases: ["gbp", "pound", "pounds", "british pound"]),
        Currency(code: "JPY", aliases: ["jpy", "yen", "japanese yen"]),
        Currency(code: "CNY", aliases: ["cny", "yuan", "renminbi", "china yuan"]),
        Currency(code: "CAD", aliases: ["cad", "canadian dollar", "canadian dollars"]),
        Currency(code: "AUD", aliases: ["aud", "australian dollar", "australian dollars"]),
        Currency(code: "CHF", aliases: ["chf", "swiss franc", "swiss francs"]),
    ]
}
