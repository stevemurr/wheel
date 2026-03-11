import Foundation

enum WidgetPromptTemplateFactory {
    static func manifest(for prompt: String) -> WidgetManifest? {
        if let intent = ClockIntent(prompt: prompt) {
            if intent.locations.count <= 1 {
                return singleClockManifest(for: intent)
            }

            return multiClockManifest(for: intent)
        }

        if let intent = CryptoTrendIntent(prompt: prompt) {
            return cryptoTrendManifest(for: intent)
        }

        if let intent = StockTrendIntent(prompt: prompt) {
            return stockTrendManifest(for: intent)
        }

        return nil
    }

    private static func singleClockManifest(for intent: ClockIntent) -> WidgetManifest {
        let location = intent.locations.first
        var params: [String: AnyCodable] = [
            "showTimeZone": AnyCodable(true),
            "includeSeconds": AnyCodable(true),
        ]

        if let location {
            params["timeZone"] = AnyCodable(location.identifier)
            params["label"] = AnyCodable(location.label)
        }

        return WidgetManifest(
            widgetType: .text,
            config: .text(
                TextConfig(
                    title: location?.singleTitle ?? "Clock",
                    markdown: false
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .currentDateTime,
                    params: params,
                    outputKey: "clock"
                ),
            ],
            returns: "clock",
            ttl: 0,
            prompt: intent.prompt
        )
    }

    private static func multiClockManifest(for intent: ClockIntent) -> WidgetManifest {
        let locations = intent.locations
        var skillChain: [WidgetSkillStep] = []

        for (index, location) in locations.enumerated() {
            skillChain.append(
                WidgetSkillStep(
                    step: index + 1,
                    skill: .currentDateTime,
                    params: [
                        "timeZone": AnyCodable(location.identifier),
                        "label": AnyCodable(location.label),
                        "showTimeZone": AnyCodable(true),
                        "includeSeconds": AnyCodable(true),
                    ],
                    outputKey: "\(location.outputKeyPrefix)Clock"
                )
            )
        }

        let dataRefs = locations.map { "$\($0.outputKeyPrefix)Clock" }
        skillChain.append(
            WidgetSkillStep(
                step: skillChain.count + 1,
                skill: .transform,
                params: [
                    "data": AnyCodable(dataRefs),
                    "mapping": AnyCodable([
                        "label": "label",
                        "time": "formatted",
                        "timeZone": "timeZoneAbbreviation",
                    ]),
                ],
                outputKey: "clockList"
            )
        )

        return WidgetManifest(
            widgetType: .list,
            config: .list(
                ListConfig(
                    title: multiClockTitle(for: locations),
                    labelField: "label",
                    valueField: "time",
                    subtitleField: "timeZone",
                    badgeField: nil,
                    captionField: nil,
                    iconField: nil,
                    linkField: nil,
                    maxItems: locations.count,
                    variant: .compact
                )
            ),
            skillChain: skillChain,
            returns: "clockList",
            ttl: 0,
            prompt: intent.prompt
        )
    }

    private static func multiClockTitle(for locations: [ClockLocation]) -> String {
        let labels = locations.map(\.label)
        if labels.count == 2 {
            return "\(labels[0]) and \(labels[1])"
        }
        if labels.count == 3 {
            return "\(labels[0]), \(labels[1]), and \(labels[2])"
        }
        return "World Clocks"
    }

    static func makeStockTrendManifest(
        symbol: String,
        title: String,
        prompt: String,
        rangeLabel: String = "30D",
        pointLimit: Int = 30,
        color: String = "#ff6b35"
    ) -> WidgetManifest {
        let sanitizedSymbol = symbol
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let url = "https://www.pocketportfolio.app/api/tickers/\(sanitizedSymbol)/json"

        return WidgetManifest(
            widgetType: .lineChart,
            config: .lineChart(
                LineChartConfig(
                    title: title,
                    xField: "date",
                    series: [
                        LineChartSeries(field: "close", label: sanitizedSymbol, color: color),
                    ],
                    yPrefix: "$",
                    showPoints: max(pointLimit, 2) <= 14
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .fetchUrl,
                    params: [
                        "url": AnyCodable(url),
                    ],
                    outputKey: "raw"
                ),
                WidgetSkillStep(
                    step: 2,
                    skill: .parseJson,
                    params: [
                        "json": AnyCodable("$raw"),
                        "path": AnyCodable("data"),
                    ],
                    outputKey: "history"
                ),
                WidgetSkillStep(
                    step: 3,
                    skill: .filterSort,
                    params: [
                        "data": AnyCodable("$history"),
                        "sortBy": AnyCodable("date"),
                        "ascending": AnyCodable(false),
                        "limit": AnyCodable(max(pointLimit, 2)),
                    ],
                    outputKey: "recentHistory"
                ),
                WidgetSkillStep(
                    step: 4,
                    skill: .filterSort,
                    params: [
                        "data": AnyCodable("$recentHistory"),
                        "sortBy": AnyCodable("date"),
                        "ascending": AnyCodable(true),
                    ],
                    outputKey: "orderedHistory"
                ),
                WidgetSkillStep(
                    step: 5,
                    skill: .transform,
                    params: [
                        "data": AnyCodable("$orderedHistory"),
                        "mapping": AnyCodable([
                            "date": "expr:new Date(item.date).toLocaleDateString()",
                            "close": "close",
                        ]),
                    ],
                    outputKey: "chartData"
                ),
            ],
            returns: "chartData",
            ttl: 1800,
            prompt: prompt.isEmpty ? "\(sanitizedSymbol) price trend (\(rangeLabel))" : prompt
        )
    }

    private static func stockTrendManifest(for intent: StockTrendIntent) -> WidgetManifest {
        makeStockTrendManifest(
            symbol: intent.stock.symbol,
            title: "\(intent.stock.symbol) Price (\(intent.range.label))",
            prompt: intent.prompt,
            rangeLabel: intent.range.label,
            pointLimit: intent.range.pointLimit,
            color: intent.stock.color
        )
    }

    static func makeCryptoTrendManifest(
        assetID: String,
        symbol: String,
        title: String,
        prompt: String,
        rangeLabel: String = "30D",
        dayCount: Int = 30,
        color: String = "#f7931a"
    ) -> WidgetManifest {
        let url = coinGeckoMarketChartURL(assetID: assetID, dayCount: dayCount)

        return WidgetManifest(
            widgetType: .lineChart,
            config: .lineChart(
                LineChartConfig(
                    title: title,
                    xField: "date",
                    series: [
                        LineChartSeries(field: "price", label: symbol, color: color),
                    ],
                    yPrefix: "$",
                    showPoints: max(dayCount, 2) <= 14
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .fetchUrl,
                    params: [
                        "url": AnyCodable(url),
                    ],
                    outputKey: "raw"
                ),
                WidgetSkillStep(
                    step: 2,
                    skill: .parseJson,
                    params: [
                        "json": AnyCodable("$raw"),
                        "path": AnyCodable("prices"),
                    ],
                    outputKey: "history"
                ),
                WidgetSkillStep(
                    step: 3,
                    skill: .transform,
                    params: [
                        "data": AnyCodable("$history"),
                        "mapping": AnyCodable([
                            "date": "expr:new Date(item[0]).toLocaleDateString()",
                            "price": "[1]",
                        ]),
                    ],
                    outputKey: "chartData"
                ),
            ],
            returns: "chartData",
            ttl: 1800,
            prompt: prompt.isEmpty ? "\(symbol) price trend (\(rangeLabel))" : prompt
        )
    }

    private static func cryptoTrendManifest(for intent: CryptoTrendIntent) -> WidgetManifest {
        makeCryptoTrendManifest(
            assetID: intent.asset.id,
            symbol: intent.asset.symbol,
            title: "\(intent.asset.name) Price (\(intent.range.label))",
            prompt: intent.prompt,
            rangeLabel: intent.range.label,
            dayCount: intent.range.dayCount,
            color: intent.asset.color
        )
    }

    private static func coinGeckoMarketChartURL(assetID: String, dayCount: Int) -> String {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(assetID)/market_chart")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: "\(max(dayCount, 2))"),
            URLQueryItem(name: "interval", value: "daily"),
        ]
        return components.url!.absoluteString
    }
}

private struct ClockIntent {
    let prompt: String
    let locations: [ClockLocation]

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = PromptText.normalize(trimmedPrompt, preservingSlash: true)
        let locations = PromptText.deduplicated(ClockLocation.catalog.filter { $0.matches(in: normalizedPrompt) })

        let hasExplicitClockIntent = Self.containsClockIntent(in: normalizedPrompt)
        let mentionsTimeWord = PromptText.containsWord("time", in: normalizedPrompt)
            || PromptText.containsWord("times", in: normalizedPrompt)
        guard hasExplicitClockIntent || (!locations.isEmpty && mentionsTimeWord) else {
            return nil
        }

        self.prompt = trimmedPrompt
        self.locations = locations
    }

    private static func containsClockIntent(in prompt: String) -> Bool {
        PromptText.containsWord("clock", in: prompt)
            || PromptText.containsPhrase("current time", in: prompt)
            || PromptText.containsPhrase("time now", in: prompt)
            || PromptText.containsPhrase("time in", in: prompt)
            || PromptText.containsPhrase("times in", in: prompt)
            || PromptText.containsPhrase("world clock", in: prompt)
    }
}

private struct ClockLocation: Hashable {
    let label: String
    let singleTitle: String
    let identifier: String
    let aliases: [String]

    var outputKeyPrefix: String {
        label
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    func matches(in prompt: String) -> Bool {
        aliases.contains { alias in
            Self.contains(alias: alias, in: prompt)
        }
    }

    private static func contains(alias: String, in prompt: String) -> Bool {
        let normalizedAlias = PromptText.normalize(alias, preservingSlash: true)
        if normalizedAlias.contains(" ") || normalizedAlias.contains("/") {
            return prompt.contains(normalizedAlias)
        }

        return PromptText.containsWord(normalizedAlias, in: prompt)
    }

    static let catalog: [ClockLocation] = [
        ClockLocation(
            label: "Pacific",
            singleTitle: "Pacific Clock",
            identifier: "America/Los_Angeles",
            aliases: ["pst", "pdt", "pt", "pacific", "pacific time", "los angeles", "san francisco", "seattle"]
        ),
        ClockLocation(
            label: "Mountain",
            singleTitle: "Mountain Clock",
            identifier: "America/Denver",
            aliases: ["mst", "mdt", "mt", "mountain", "mountain time", "denver", "phoenix"]
        ),
        ClockLocation(
            label: "Central",
            singleTitle: "Central Clock",
            identifier: "America/Chicago",
            aliases: ["cst", "cdt", "ct", "central", "central time", "chicago", "dallas", "austin"]
        ),
        ClockLocation(
            label: "Eastern",
            singleTitle: "Eastern Clock",
            identifier: "America/New_York",
            aliases: ["est", "edt", "et", "eastern", "eastern time", "new york", "nyc", "boston", "miami"]
        ),
        ClockLocation(
            label: "Beijing",
            singleTitle: "Beijing Clock",
            identifier: "Asia/Shanghai",
            aliases: ["beijing", "china", "china time", "china standard time", "cst china", "shanghai"]
        ),
        ClockLocation(
            label: "Tokyo",
            singleTitle: "Tokyo Clock",
            identifier: "Asia/Tokyo",
            aliases: ["tokyo", "jst", "japan", "japan time"]
        ),
        ClockLocation(
            label: "Seoul",
            singleTitle: "Seoul Clock",
            identifier: "Asia/Seoul",
            aliases: ["seoul", "kst", "korea", "korea time"]
        ),
        ClockLocation(
            label: "Singapore",
            singleTitle: "Singapore Clock",
            identifier: "Asia/Singapore",
            aliases: ["singapore", "sgt", "singapore time"]
        ),
        ClockLocation(
            label: "London",
            singleTitle: "London Clock",
            identifier: "Europe/London",
            aliases: ["london", "uk", "uk time", "british time", "gmt"]
        ),
        ClockLocation(
            label: "Paris",
            singleTitle: "Paris Clock",
            identifier: "Europe/Paris",
            aliases: ["paris", "france", "france time", "cet", "cest"]
        ),
        ClockLocation(
            label: "Berlin",
            singleTitle: "Berlin Clock",
            identifier: "Europe/Berlin",
            aliases: ["berlin", "germany", "germany time"]
        ),
        ClockLocation(
            label: "Sydney",
            singleTitle: "Sydney Clock",
            identifier: "Australia/Sydney",
            aliases: ["sydney", "aest", "aedt", "australia", "australia time"]
        ),
        ClockLocation(
            label: "UTC",
            singleTitle: "UTC Clock",
            identifier: "UTC",
            aliases: ["utc", "zulu", "universal time"]
        ),
    ]
}

private struct CryptoTrendIntent {
    struct RangeSelection {
        let label: String
        let dayCount: Int
    }

    struct Asset: Hashable {
        let id: String
        let name: String
        let symbol: String
        let aliases: [String]
        let color: String

        func matches(in prompt: String) -> Bool {
            aliases.contains { alias in
                Self.contains(alias: alias, in: prompt)
            }
        }

        private static func contains(alias: String, in prompt: String) -> Bool {
            let normalizedAlias = PromptText.normalize(alias)
            if normalizedAlias.contains(" ") {
                return prompt.contains(normalizedAlias)
            }

            return PromptText.containsWord(normalizedAlias, in: prompt)
        }
    }

    let prompt: String
    let asset: Asset
    let range: RangeSelection

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = PromptText.normalize(trimmedPrompt)
        let explicitRange = Self.extractRange(from: normalizedPrompt)
        let range = explicitRange ?? RangeSelection(label: "30D", dayCount: 30)

        guard Self.containsTrendIntent(in: normalizedPrompt, hasExplicitRange: explicitRange != nil) else {
            return nil
        }

        let matchedAssets = PromptText.deduplicated(Self.catalog.filter { $0.matches(in: normalizedPrompt) })
        guard let asset = matchedAssets.first else { return nil }

        self.prompt = trimmedPrompt
        self.asset = asset
        self.range = range
    }

    private static func containsTrendIntent(in prompt: String, hasExplicitRange: Bool) -> Bool {
        PromptText.containsWord("chart", in: prompt)
            || PromptText.containsWord("graph", in: prompt)
            || PromptText.containsWord("trend", in: prompt)
            || PromptText.containsWord("history", in: prompt)
            || PromptText.containsWord("historical", in: prompt)
            || PromptText.containsPhrase("over time", in: prompt)
            || PromptText.containsPhrase("line chart", in: prompt)
            || (hasExplicitRange && PromptText.containsWord("price", in: prompt))
    }

    private static func extractRange(from prompt: String) -> RangeSelection? {
        let pattern = #"\b(\d+)\s*(d|day|days|w|week|weeks|m|mo|mon|month|months|y|yr|year|years)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(prompt.startIndex..., in: prompt)
        let selections = regex.matches(in: prompt, range: nsRange).compactMap { match -> RangeSelection? in
            guard let valueRange = Range(match.range(at: 1), in: prompt),
                  let unitRange = Range(match.range(at: 2), in: prompt),
                  let value = Int(prompt[valueRange]) else {
                return nil
            }

            let unit = String(prompt[unitRange])
            switch unit {
            case "d", "day", "days":
                return RangeSelection(label: "\(value)D", dayCount: min(max(value, 2), 90))
            case "w", "week", "weeks":
                return RangeSelection(label: "\(value)W", dayCount: min(max(value * 7, 7), 180))
            case "m", "mo", "mon", "month", "months":
                return RangeSelection(label: "\(value)M", dayCount: min(max(value * 30, 14), 365))
            case "y", "yr", "year", "years":
                return RangeSelection(label: "\(value)Y", dayCount: min(max(value * 365, 60), 730))
            default:
                return nil
            }
        }

        return selections.max(by: { $0.dayCount < $1.dayCount })
    }

    private static let catalog: [Asset] = [
        Asset(id: "bitcoin", name: "Bitcoin", symbol: "BTC", aliases: ["bitcoin", "btc"], color: "#f7931a"),
        Asset(id: "ethereum", name: "Ethereum", symbol: "ETH", aliases: ["ethereum", "eth"], color: "#627eea"),
        Asset(id: "solana", name: "Solana", symbol: "SOL", aliases: ["solana", "sol"], color: "#14f195"),
        Asset(id: "ripple", name: "XRP", symbol: "XRP", aliases: ["xrp", "ripple"], color: "#23292f"),
        Asset(id: "cardano", name: "Cardano", symbol: "ADA", aliases: ["cardano", "ada"], color: "#2a6df4"),
        Asset(id: "dogecoin", name: "Dogecoin", symbol: "DOGE", aliases: ["dogecoin", "doge"], color: "#c2a633"),
    ]
}

private struct StockTrendIntent {
    struct RangeSelection {
        let label: String
        let pointLimit: Int
    }

    struct Stock: Hashable {
        let symbol: String
        let name: String
        let aliases: [String]
        let color: String

        func matches(in prompt: String) -> Bool {
            aliases.contains { alias in
                Self.contains(alias: alias, in: prompt)
            }
        }

        private static func contains(alias: String, in prompt: String) -> Bool {
            let normalizedAlias = PromptText.normalize(alias)
            if normalizedAlias.contains(" ") {
                return prompt.contains(normalizedAlias)
            }

            return PromptText.containsWord(normalizedAlias, in: prompt)
        }
    }

    let prompt: String
    let stock: Stock
    let range: RangeSelection

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = PromptText.normalize(trimmedPrompt)
        let range = Self.extractRange(from: normalizedPrompt) ?? RangeSelection(label: "30D", pointLimit: 30)

        guard Self.containsTrendIntent(in: normalizedPrompt, hasExplicitRange: Self.extractRange(from: normalizedPrompt) != nil) else {
            return nil
        }

        let matchedStocks = PromptText.deduplicated(Self.catalog.filter { $0.matches(in: normalizedPrompt) })
        if let stock = matchedStocks.first {
            self.prompt = trimmedPrompt
            self.stock = stock
            self.range = range
            return
        }

        guard Self.containsStockContext(in: normalizedPrompt),
              let ticker = Self.extractTicker(from: trimmedPrompt) else {
            return nil
        }

        self.prompt = trimmedPrompt
        self.stock = Stock(
            symbol: ticker,
            name: ticker,
            aliases: [ticker.lowercased()],
            color: "#ff6b35"
        )
        self.range = range
    }

    private static func containsTrendIntent(in prompt: String, hasExplicitRange: Bool) -> Bool {
        PromptText.containsWord("chart", in: prompt)
            || PromptText.containsWord("graph", in: prompt)
            || PromptText.containsWord("trend", in: prompt)
            || PromptText.containsWord("history", in: prompt)
            || PromptText.containsWord("historical", in: prompt)
            || PromptText.containsPhrase("over time", in: prompt)
            || (hasExplicitRange && PromptText.containsWord("price", in: prompt))
            || (hasExplicitRange && containsStockContext(in: prompt))
    }

    private static func containsStockContext(in prompt: String) -> Bool {
        PromptText.containsWord("stock", in: prompt)
            || PromptText.containsWord("stocks", in: prompt)
            || PromptText.containsWord("ticker", in: prompt)
            || PromptText.containsWord("share", in: prompt)
            || PromptText.containsWord("shares", in: prompt)
            || PromptText.containsWord("equity", in: prompt)
            || PromptText.containsWord("equities", in: prompt)
            || prompt.contains("nasdaq")
            || prompt.contains("nyse")
    }

    private static func extractRange(from prompt: String) -> RangeSelection? {
        let pattern = #"\b(\d+)\s*(d|day|days|w|week|weeks|m|mo|mon|month|months|y|yr|year|years)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(prompt.startIndex..., in: prompt)
        let selections = regex.matches(in: prompt, range: nsRange).compactMap { match -> RangeSelection? in
            guard let valueRange = Range(match.range(at: 1), in: prompt),
                  let unitRange = Range(match.range(at: 2), in: prompt),
                  let value = Int(prompt[valueRange]) else {
                return nil
            }

            let unit = String(prompt[unitRange])
            switch unit {
            case "d", "day", "days":
                return RangeSelection(label: "\(value)D", pointLimit: min(max(value, 2), 90))
            case "w", "week", "weeks":
                return RangeSelection(label: "\(value)W", pointLimit: min(max(value * 7, 7), 120))
            case "m", "mo", "mon", "month", "months":
                return RangeSelection(label: "\(value)M", pointLimit: min(max(value * 30, 14), 180))
            case "y", "yr", "year", "years":
                return RangeSelection(label: "\(value)Y", pointLimit: min(max(value * 252, 60), 252))
            default:
                return nil
            }
        }

        return selections.max(by: { $0.pointLimit < $1.pointLimit })
    }

    private static func extractTicker(from prompt: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z]{1,5}\b"#) else {
            return nil
        }

        let nsRange = NSRange(prompt.startIndex..., in: prompt)
        for match in regex.matches(in: prompt, range: nsRange) {
            guard let range = Range(match.range, in: prompt) else { continue }
            let ticker = String(prompt[range])
            if ticker.count >= 1, ticker.count <= 5 {
                return ticker
            }
        }

        return nil
    }

    private static let catalog: [Stock] = [
        Stock(symbol: "AMD", name: "Advanced Micro Devices", aliases: ["amd", "advanced micro devices"], color: "#ff6b35"),
        Stock(symbol: "AAPL", name: "Apple", aliases: ["aapl", "apple"], color: "#4f7cff"),
        Stock(symbol: "AMZN", name: "Amazon", aliases: ["amzn", "amazon"], color: "#ff9900"),
        Stock(symbol: "GOOGL", name: "Alphabet", aliases: ["googl", "google", "alphabet"], color: "#1a73e8"),
        Stock(symbol: "META", name: "Meta", aliases: ["meta", "facebook"], color: "#1877f2"),
        Stock(symbol: "MSFT", name: "Microsoft", aliases: ["msft", "microsoft"], color: "#5e5ce6"),
        Stock(symbol: "NFLX", name: "Netflix", aliases: ["nflx", "netflix"], color: "#e50914"),
        Stock(symbol: "NVDA", name: "NVIDIA", aliases: ["nvda", "nvidia"], color: "#76b900"),
        Stock(symbol: "TSLA", name: "Tesla", aliases: ["tsla", "tesla"], color: "#cc2d2d"),
    ]
}
