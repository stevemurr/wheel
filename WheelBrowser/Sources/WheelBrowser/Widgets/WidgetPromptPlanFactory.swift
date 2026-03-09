import Foundation

enum WidgetPromptPlanFactory {
    static func plan(for prompt: String) -> GeneratedWidgetPlan? {
        if let intent = HackerNewsPromptIntent(prompt: prompt) {
            return intent.plan
        }
        if let intent = SubredditPromptIntent(prompt: prompt) {
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
        let normalizedPrompt = PromptText.normalize(trimmedPrompt)

        guard Self.referencesHackerNews(in: normalizedPrompt) else { return nil }
        guard Self.containsStoryIntent(in: normalizedPrompt) else { return nil }

        self.prompt = trimmedPrompt
        self.limit = PromptText.extractInteger(in: #"\b([1-9]|1[0-9]|20)\b"#, from: normalizedPrompt) ?? 5
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
            || PromptText.containsWord("hn", in: prompt)
    }

    private static func containsStoryIntent(in prompt: String) -> Bool {
        prompt.contains("front page")
            || PromptText.containsWord("headline", in: prompt)
            || PromptText.containsWord("headlines", in: prompt)
            || PromptText.containsWord("story", in: prompt)
            || PromptText.containsWord("stories", in: prompt)
            || PromptText.containsWord("article", in: prompt)
            || PromptText.containsWord("articles", in: prompt)
            || PromptText.containsWord("post", in: prompt)
            || PromptText.containsWord("posts", in: prompt)
            || PromptText.containsWord("top", in: prompt)
            || PromptText.containsWord("best", in: prompt)
    }
}

private struct SubredditPromptIntent {
    private enum Sort: String {
        case hot
        case new
        case top
    }

    let prompt: String
    let subreddit: String
    let limit: Int
    private let sort: Sort

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = PromptText.normalize(trimmedPrompt, preservingSlash: true)

        guard Self.referencesSubreddit(in: trimmedPrompt, normalizedPrompt: normalizedPrompt) else { return nil }
        guard Self.containsStoryIntent(in: normalizedPrompt) else { return nil }
        guard let subreddit = Self.extractSubreddit(from: trimmedPrompt, normalizedPrompt: normalizedPrompt) else { return nil }

        self.prompt = trimmedPrompt
        self.subreddit = subreddit
        self.limit = PromptText.extractInteger(in: #"\b([1-9]|1[0-9]|2[0-5])\b"#, from: normalizedPrompt) ?? 5
        self.sort = Self.resolveSort(from: normalizedPrompt)
    }

    var plan: GeneratedWidgetPlan {
        GeneratedWidgetPlan(
            title: Self.title(for: subreddit, limit: limit, sort: sort),
            widgetType: "list",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: Self.redditListingURL(subreddit: subreddit, sort: sort, limit: limit),
                jsonPath: "data.children",
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
                variant: sort == .top ? "ranked" : "feed",
                labelField: "data.title",
                valueField: "data.score",
                subtitleField: "data.author",
                badgeField: nil,
                captionField: nil,
                iconField: nil,
                linkField: "data.url",
                maxItems: limit
            ),
            table: nil,
            chart: nil
        )
    }

    private static func redditListingURL(subreddit: String, sort: Sort, limit: Int) -> String {
        var components = URLComponents(string: "https://www.reddit.com/r/\(subreddit)/\(sort.rawValue).json")!
        var queryItems = [
            URLQueryItem(name: "raw_json", value: "1"),
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 25)))"),
        ]
        if sort == .top {
            queryItems.append(URLQueryItem(name: "t", value: "day"))
        }
        components.queryItems = queryItems
        return components.url!.absoluteString
    }

    private static func title(for subreddit: String, limit: Int, sort: Sort) -> String {
        let noun = limit == 1 ? "Post" : "Posts"
        switch sort {
        case .top:
            return "Top \(limit) \(noun) on r/\(subreddit)"
        case .new:
            return limit == 1 ? "Latest Post on r/\(subreddit)" : "Latest \(noun) on r/\(subreddit)"
        case .hot:
            return limit == 1 ? "Hot Post on r/\(subreddit)" : "Hot \(noun) on r/\(subreddit)"
        }
    }

    private static func resolveSort(from prompt: String) -> Sort {
        if PromptText.containsWord("new", in: prompt)
            || PromptText.containsWord("latest", in: prompt)
            || PromptText.containsWord("recent", in: prompt)
            || PromptText.containsWord("fresh", in: prompt) {
            return .new
        }
        if PromptText.containsWord("hot", in: prompt)
            || PromptText.containsWord("trending", in: prompt)
            || PromptText.containsWord("popular", in: prompt) {
            return .hot
        }
        return .top
    }

    private static func referencesSubreddit(in prompt: String, normalizedPrompt: String) -> Bool {
        if prompt.range(of: #"\br/[A-Za-z0-9_]+\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return normalizedPrompt.range(
            of: #"\bsub+redd?it\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsStoryIntent(in prompt: String) -> Bool {
        prompt.contains("front page")
            || PromptText.containsWord("headline", in: prompt)
            || PromptText.containsWord("headlines", in: prompt)
            || PromptText.containsWord("story", in: prompt)
            || PromptText.containsWord("stories", in: prompt)
            || PromptText.containsWord("article", in: prompt)
            || PromptText.containsWord("articles", in: prompt)
            || PromptText.containsWord("post", in: prompt)
            || PromptText.containsWord("posts", in: prompt)
            || PromptText.containsWord("top", in: prompt)
            || PromptText.containsWord("best", in: prompt)
            || PromptText.containsWord("hot", in: prompt)
            || PromptText.containsWord("latest", in: prompt)
            || PromptText.containsWord("recent", in: prompt)
            || PromptText.containsWord("new", in: prompt)
    }

    private static func extractSubreddit(from prompt: String, normalizedPrompt: String) -> String? {
        if let range = prompt.range(
            of: #"\br/([A-Za-z0-9_]+)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let value = String(prompt[range]).dropFirst(2)
            return String(value).lowercased()
        }

        if let match = normalizedPrompt.range(
            of: #"\b([a-z0-9_]+)\s+sub+redd?it\b"#,
            options: .regularExpression
        ) {
            let words = normalizedPrompt[match]
                .split(separator: " ", omittingEmptySubsequences: true)
            if let candidate = words.first, candidate != "the", candidate != "a", candidate != "an" {
                return String(candidate).lowercased()
            }
        }

        return nil
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
        let normalizedPrompt = PromptText.normalize(trimmedPrompt)
        let assets = PromptText.deduplicated(Self.catalog.filter { asset in
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
        PromptText.containsWord("price", in: prompt)
            || PromptText.containsWord("prices", in: prompt)
            || PromptText.containsWord("watchlist", in: prompt)
            || PromptText.containsWord("track", in: prompt)
            || PromptText.containsWord("quote", in: prompt)
            || PromptText.containsWord("quotes", in: prompt)
            || PromptText.containsWord("crypto", in: prompt)
            || PromptText.containsWord("coin", in: prompt)
            || PromptText.containsWord("coins", in: prompt)
            || PromptText.containsWord("token", in: prompt)
            || PromptText.containsWord("tokens", in: prompt)
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
        let normalizedAlias = PromptText.normalize(alias)
        if normalizedAlias.contains(" ") {
            return prompt.contains(normalizedAlias)
        }
        return PromptText.containsWord(normalizedAlias, in: prompt)
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
        let normalizedPrompt = PromptText.normalize(trimmedPrompt)
        guard !normalizedPrompt.contains(where: \.isNumber) else { return nil }

        let matches = PromptText.deduplicated(Self.catalog.filter { currency in
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
        PromptText.containsWord("exchange", in: prompt)
            || PromptText.containsWord("rate", in: prompt)
            || PromptText.containsWord("fx", in: prompt)
            || PromptText.containsWord("forex", in: prompt)
            || PromptText.containsWord("currency", in: prompt)
            || prompt.contains(" to ")
            || prompt.contains(" against ")
    }

    private static func contains(alias: String, in prompt: String) -> Bool {
        let normalizedAlias = PromptText.normalize(alias)
        return PromptText.containsWord(normalizedAlias, in: prompt)
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
