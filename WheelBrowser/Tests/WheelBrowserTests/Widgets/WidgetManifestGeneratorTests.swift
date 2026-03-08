import Foundation
import FoundationModels
import Testing
@testable import WheelBrowser

@Suite("WidgetManifestGenerator")
struct WidgetManifestGeneratorTests {
    @Test("Generator compiles a structured plan into a validated manifest")
    func generatesManifest() async throws {
        let preflight = PreflightRecorder()
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                GeneratedWidgetPlan(
                    title: "Greeting",
                    widgetType: "text",
                    source: GeneratedWidgetSourcePlan(
                        kind: "literalText",
                        url: nil,
                        jsonPath: nil,
                        resultShape: nil,
                        sortBy: nil,
                        sortAscending: nil,
                        limit: nil,
                        timeZones: nil
                    ),
                    refreshSeconds: 300,
                    prompt: "Show hello",
                    text: GeneratedWidgetTextPlan(
                        contentField: nil,
                        literalContent: "Hello",
                        markdown: false,
                        showTimeZone: nil,
                        includeSeconds: nil
                    ),
                    metric: nil,
                    list: nil,
                    table: nil,
                    chart: nil
                )
            },
            preflightProvider: { manifest in
                await preflight.record(manifest.id)
            }
        )

        let manifest = try await generator.generate(prompt: "Show hello")
        #expect(manifest.widgetType == .text)
        #expect(manifest.returns == "textData")
        #expect(manifest.skillChain.count == 1)
        #expect(manifest.skillChain.first?.skill == .transform)
        #expect(manifest.prompt == "Show hello")

        guard case .text(let config) = manifest.config else {
            Issue.record("Expected text config")
            return
        }

        #expect(config.title == "Greeting")
        #expect(config.markdown == false)
        #expect(await preflight.ids == [manifest.id])
    }

    @Test("Generator surfaces compilation errors from an invalid plan")
    func validationFailure() async {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                GeneratedWidgetPlan(
                    title: "Broken",
                    widgetType: "list",
                    source: GeneratedWidgetSourcePlan(
                        kind: "literalText",
                        url: nil,
                        jsonPath: nil,
                        resultShape: nil,
                        sortBy: nil,
                        sortAscending: nil,
                        limit: nil,
                        timeZones: nil
                    ),
                    refreshSeconds: 300,
                    prompt: "Broken",
                    text: GeneratedWidgetTextPlan(
                        contentField: nil,
                        literalContent: "Broken",
                        markdown: false,
                        showTimeZone: nil,
                        includeSeconds: nil
                    ),
                    metric: nil,
                    list: nil,
                    table: nil,
                    chart: nil
                )
            },
            preflightProvider: { _ in
                Issue.record("Preflight should not run for an invalid compiled plan.")
            }
        )

        await #expect(throws: WidgetManifestGenerationError.validationFailed("Widget type 'list' is not supported with source kind 'literalText'.")) {
            try await generator.generate(prompt: "Broken")
        }
    }

    @Test("Generator canonicalizes plan aliases before compilation")
    func normalizesAliases() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                GeneratedWidgetPlan(
                    title: "North Star",
                    widgetType: "stat_card",
                    source: GeneratedWidgetSourcePlan(
                        kind: "api",
                        url: "https://example.com/metric.json",
                        jsonPath: nil,
                        resultShape: "single",
                        sortBy: nil,
                        sortAscending: nil,
                        limit: nil,
                        timeZones: nil
                    ),
                    refreshSeconds: 300,
                    prompt: nil,
                    text: nil,
                    metric: GeneratedWidgetMetricPlan(
                        valueField: "active_users",
                        changeField: "change",
                        changePercentField: nil,
                        changeIsPercent: nil,
                        prefix: nil,
                        suffix: nil,
                        footnote: nil
                    ),
                    list: nil,
                    table: nil,
                    chart: nil
                )
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Show me the north star metric")
        #expect(manifest.widgetType == .statCard)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .transform])
        #expect(manifest.prompt == "Show me the north star metric")

        guard case .statCard(let config) = manifest.config else {
            Issue.record("Expected statCard config")
            return
        }

        #expect(config.title == "North Star")
        #expect(config.valueField == "value")
        #expect(config.prefix == nil)
        #expect(config.changeField == "change")
    }

    @Test("Generator infers chart widgets from generic widget type labels")
    func infersGenericChartLabels() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                GeneratedWidgetPlan(
                    title: "Revenue Trend",
                    widgetType: "chart",
                    source: GeneratedWidgetSourcePlan(
                        kind: "jsonAPI",
                        url: "https://example.com/revenue.json",
                        jsonPath: "data",
                        resultShape: "collection",
                        sortBy: "date",
                        sortAscending: true,
                        limit: 30,
                        timeZones: nil
                    ),
                    refreshSeconds: 300,
                    prompt: "show me revenue over the last 30 days",
                    text: nil,
                    metric: nil,
                    list: nil,
                    table: nil,
                    chart: GeneratedWidgetChartPlan(
                        xField: "date",
                        yField: "close",
                        series: nil,
                        color: "#00aa88",
                        yPrefix: "$",
                        yUnit: nil,
                        showPoints: false
                    )
                )
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "show me revenue over the last 30 days")

        #expect(manifest.widgetType == .lineChart)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .transform])
    }

    @Test("Generator infers stock chart defaults when chart details are omitted")
    func infersStockChartDefaultsWithoutChartSection() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                GeneratedWidgetPlan(
                    title: "Apple Stock Over the Last 30 Days",
                    widgetType: "chart",
                    source: GeneratedWidgetSourcePlan(
                        kind: "jsonAPI",
                        url: "https://www.pocketportfolio.app/api/tickers/AAPL/json",
                        jsonPath: "data",
                        resultShape: "collection",
                        sortBy: "date",
                        sortAscending: true,
                        limit: 30,
                        timeZones: [
                            GeneratedWidgetTimeZonePlan(label: "UTC", identifier: "UTC"),
                        ]
                    ),
                    refreshSeconds: 60,
                    prompt: "show me the 30 day series",
                    text: nil,
                    metric: nil,
                    list: nil,
                    table: nil,
                    chart: nil
                )
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "show me the 30 day series")

        #expect(manifest.widgetType == .lineChart)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .transform])

        guard case .lineChart(let config) = manifest.config else {
            Issue.record("Expected lineChart config")
            return
        }

        #expect(config.yPrefix == "$")
        #expect(config.series.first?.label == "Close")
    }

    @Test("Generator uses a built-in stock template for compact range prompts")
    func usesBuiltInStockTemplateForCompactRangePrompt() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Compact stock range prompt should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Compact stock range prompt should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "show me the apple stock price over 30d")

        #expect(manifest.widgetType == .lineChart)
        #expect(manifest.skillChain.first?.params["url"]?.stringValue == "https://www.pocketportfolio.app/api/tickers/AAPL/json")
        #expect(manifest.skillChain[1].params["path"]?.stringValue == "data")

        guard case .lineChart(let config) = manifest.config else {
            Issue.record("Expected lineChart config")
            return
        }

        #expect(config.title == "AAPL Price (30D)")
        #expect(config.series.first?.label == "AAPL")
    }

    @Test("Generator repairs an invalid first plan")
    func repairsInvalidPlan() async throws {
        let sequence = PlanSequence(responses: [
            GeneratedWidgetPlan(
                title: "Broken",
                widgetType: "priceCard",
                source: GeneratedWidgetSourcePlan(
                    kind: "jsonAPI",
                    url: "https://example.com/quote.json",
                    jsonPath: nil,
                    resultShape: "single",
                    sortBy: nil,
                    sortAscending: nil,
                    limit: nil,
                    timeZones: nil
                ),
                refreshSeconds: 300,
                prompt: "Broken",
                text: nil,
                metric: nil,
                list: nil,
                table: nil,
                chart: nil
            ),
            GeneratedWidgetPlan(
                title: "Fixed",
                widgetType: "text",
                source: GeneratedWidgetSourcePlan(
                    kind: "literalText",
                    url: nil,
                    jsonPath: nil,
                    resultShape: nil,
                    sortBy: nil,
                    sortAscending: nil,
                    limit: nil,
                    timeZones: nil
                ),
                refreshSeconds: 300,
                prompt: "Fixed",
                text: GeneratedWidgetTextPlan(
                    contentField: nil,
                    literalContent: "Hello",
                    markdown: false,
                    showTimeZone: nil,
                    includeSeconds: nil
                ),
                metric: nil,
                list: nil,
                table: nil,
                chart: nil
            ),
        ])

        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                try await sequence.next()
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Show hello")
        #expect(manifest.widgetType == .text)
        #expect(manifest.prompt == "Fixed")
        #expect(await sequence.callCount == 2)
    }

    @Test("Generator repairs when hidden preflight fails")
    func repairsAfterPreflightFailure() async throws {
        let sequence = PlanSequence(responses: [
            GeneratedWidgetPlan(
                title: "Broken",
                widgetType: "text",
                source: GeneratedWidgetSourcePlan(
                    kind: "literalText",
                    url: nil,
                    jsonPath: nil,
                    resultShape: nil,
                    sortBy: nil,
                    sortAscending: nil,
                    limit: nil,
                    timeZones: nil
                ),
                refreshSeconds: 300,
                prompt: "Broken",
                text: GeneratedWidgetTextPlan(
                    contentField: nil,
                    literalContent: "Broken",
                    markdown: false,
                    showTimeZone: nil,
                    includeSeconds: nil
                ),
                metric: nil,
                list: nil,
                table: nil,
                chart: nil
            ),
            GeneratedWidgetPlan(
                title: "Fixed",
                widgetType: "text",
                source: GeneratedWidgetSourcePlan(
                    kind: "literalText",
                    url: nil,
                    jsonPath: nil,
                    resultShape: nil,
                    sortBy: nil,
                    sortAscending: nil,
                    limit: nil,
                    timeZones: nil
                ),
                refreshSeconds: 300,
                prompt: "Fixed",
                text: GeneratedWidgetTextPlan(
                    contentField: nil,
                    literalContent: "Fixed",
                    markdown: false,
                    showTimeZone: nil,
                    includeSeconds: nil
                ),
                metric: nil,
                list: nil,
                table: nil,
                chart: nil
            ),
        ])
        let preflight = FailingOncePreflight()

        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                try await sequence.next()
            },
            preflightProvider: { manifest in
                try await preflight.run(for: manifest)
            }
        )

        let manifest = try await generator.generate(prompt: "Show hello")
        #expect(manifest.prompt == "Fixed")
        #expect(await sequence.callCount == 2)
        #expect(await preflight.callCount == 2)
    }

    @Test("Generator uses a built-in clock template for timezone prompts")
    func usesClockTemplate() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Clock template should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Clock template should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Create a PST clock widget")

        #expect(manifest.widgetType == .text)
        #expect(manifest.skillChain.count == 1)
        #expect(manifest.skillChain.first?.skill == .currentDateTime)
        #expect(manifest.skillChain.first?.params["timeZone"]?.stringValue == "America/Los_Angeles")
        #expect(manifest.returns == "clock")

        guard case .text(let config) = manifest.config else {
            Issue.record("Expected text config")
            return
        }

        #expect(config.title == "Pacific Clock")
        #expect(config.markdown == false)
    }

    @Test("Built-in templates still run hidden preflight")
    func builtInTemplatePreflights() async throws {
        let preflight = PreflightRecorder()
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Clock template should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Clock template should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { manifest in
                await preflight.record(manifest.id)
            }
        )

        let manifest = try await generator.generate(prompt: "Create a PST clock widget")

        #expect(manifest.widgetType == .text)
        #expect(manifest.skillChain.count == 1)
        #expect(manifest.skillChain.first?.skill == .currentDateTime)
        #expect(manifest.skillChain.first?.params["timeZone"]?.stringValue == "America/Los_Angeles")
        #expect(manifest.returns == "clock")

        guard case .text(let config) = manifest.config else {
            Issue.record("Expected text config")
            return
        }

        #expect(config.title == "Pacific Clock")
        #expect(config.markdown == false)
        #expect(await preflight.ids == [manifest.id])
    }

    @Test("Generator uses a built-in stock trend template for stock chart prompts")
    func usesBuiltInStockTrendTemplate() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Stock trend template should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Stock trend template should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(
            prompt: "Create a widget with AMD stock price over the last 30 days as a line chart"
        )

        #expect(manifest.widgetType == .lineChart)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .filterSort, .transform])
        #expect(manifest.skillChain.first?.params["url"]?.stringValue == "https://www.pocketportfolio.app/api/tickers/AMD/json")
        #expect(manifest.skillChain[1].params["path"]?.stringValue == "data")
        #expect(manifest.returns == "chartData")

        guard case .lineChart(let config) = manifest.config else {
            Issue.record("Expected lineChart config")
            return
        }

        #expect(config.title == "AMD Price (30D)")
        #expect(config.xField == "date")
        #expect(config.series.count == 1)
        #expect(config.series.first?.field == "close")
        #expect(config.series.first?.label == "AMD")
        #expect(config.yPrefix == "$")
    }

    @Test("Generator uses a built-in finance planner for crypto watchlists")
    func usesBuiltInFinancePlanner() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Finance planner should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Finance planner should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Show BTC, ETH, and SOL prices")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .transform])
        #expect(manifest.returns == "listData")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "BTC • ETH • SOL Watchlist")
        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.badgeField == "badge")
        #expect(config.variant == .compact)
    }

    @Test("Generator uses a built-in Hacker News planner for headline prompts")
    func usesBuiltInHackerNewsPlanner() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Hacker News planner should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Hacker News planner should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Create a widget for the top 5 Hacker News articles")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .transform])
        #expect(manifest.skillChain.first?.params["url"]?.stringValue?.contains("hn.algolia.com") == true)
        #expect(manifest.returns == "listData")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Top 5 Hacker News Stories")
        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.linkField == "link")
        #expect(config.variant == .feed)
        #expect(config.maxItems == 5)
    }

    @Test("Generator uses a built-in subreddit planner for subreddit post prompts")
    func usesBuiltInSubredditPlanner() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Subreddit planner should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Subreddit planner should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Create a widget for the top 5 posts on the Swift subreddit")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .transform])
        #expect(manifest.skillChain.first?.params["url"]?.stringValue?.contains("reddit.com/r/swift/top.json") == true)
        #expect(manifest.skillChain.first?.params["url"]?.stringValue?.contains("raw_json=1") == true)
        #expect(manifest.returns == "listData")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Top 5 Posts on r/swift")
        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.linkField == "link")
        #expect(config.variant == .ranked)
        #expect(config.maxItems == 5)
    }

    @Test("Generator recognizes common subreddit typo prompts")
    func usesBuiltInSubredditPlannerForTypos() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Subreddit planner should bypass the language model for typo prompts.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Subreddit planner should not check model availability for typo prompts.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "show me the top 5 aritcles from swift subbredit")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .transform])
        #expect(manifest.skillChain.first?.params["url"]?.stringValue?.contains("reddit.com/r/swift/top.json") == true)
        #expect(manifest.skillChain.first?.params["url"]?.stringValue?.contains("t=day") == true)

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Top 5 Posts on r/swift")
        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.linkField == "link")
        #expect(config.variant == .ranked)
    }

    @Test("Generator repairs malformed Reddit child field paths from model plans")
    func repairsMalformedRedditChildPlans() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                GeneratedWidgetPlan(
                    title: "Top 5 Posts in Swift Subreddit",
                    widgetType: "list",
                    source: GeneratedWidgetSourcePlan(
                        kind: "jsonAPI",
                        url: "https://www.reddit.com/r/swift/top.json?limit=5",
                        jsonPath: "data.children",
                        resultShape: "collection",
                        sortBy: "score",
                        sortAscending: false,
                        limit: 5,
                        timeZones: nil
                    ),
                    refreshSeconds: 60,
                    prompt: "Show me a ranked list",
                    text: nil,
                    metric: nil,
                    list: GeneratedWidgetListPlan(
                        variant: "ranked",
                        labelField: "title",
                        valueField: "score",
                        subtitleField: nil,
                        badgeField: nil,
                        captionField: nil,
                        iconField: nil,
                        linkField: nil,
                        maxItems: 5
                    ),
                    table: nil,
                    chart: nil
                )
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Show me a ranked list")

        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .transform])
        #expect(manifest.skillChain[0].params["url"]?.stringValue?.contains("raw_json=1") == true)
        #expect(manifest.skillChain[0].params["url"]?.stringValue?.contains("t=day") == true)
        #expect(manifest.skillChain[2].params["sortBy"]?.stringValue == "data.score")

        let mapping = manifest.skillChain[3].params["mapping"]?.dictionaryValue
        #expect(mapping?["label"] as? String == "data.title")
        #expect(mapping?["value"] as? String == "data.score")
    }

    @Test("Generator builds multi-clock widgets from one prompt")
    func buildsMultiClockTemplate() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Clock template should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Clock template should not check model availability.")
                return .unavailable("Should not be called")
            },
            preflightProvider: { _ in }
        )

        let manifest = try await generator.generate(prompt: "Create a widget with PST and Beijing time")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.count == 3)
        #expect(manifest.skillChain[0].skill == .currentDateTime)
        #expect(manifest.skillChain[0].params["timeZone"]?.stringValue == "America/Los_Angeles")
        #expect(manifest.skillChain[1].params["timeZone"]?.stringValue == "Asia/Shanghai")
        #expect(manifest.skillChain[2].skill == .transform)
        #expect(manifest.returns == "clockList")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Pacific and Beijing")
        #expect(config.labelField == "label")
        #expect(config.valueField == "time")
        #expect(config.subtitleField == "timeZone")
        #expect(config.variant == .compact)
    }
}

private actor PlanSequence {
    private var responses: [GeneratedWidgetPlan]
    private(set) var callCount = 0

    init(responses: [GeneratedWidgetPlan]) {
        self.responses = responses
    }

    func next() throws -> GeneratedWidgetPlan {
        callCount += 1
        guard !responses.isEmpty else {
            throw TestSequenceError.depleted
        }
        return responses.removeFirst()
    }
}

private actor PreflightRecorder {
    private(set) var ids: [UUID] = []

    func record(_ id: UUID) {
        ids.append(id)
    }
}

private actor FailingOncePreflight {
    private(set) var callCount = 0

    func run(for manifest: WidgetManifest) throws {
        callCount += 1
        if callCount == 1 {
            throw WidgetManifestPreflightError.widgetFailed("Missing content field")
        }
        _ = manifest
    }
}

private enum TestSequenceError: Error {
    case depleted
}
