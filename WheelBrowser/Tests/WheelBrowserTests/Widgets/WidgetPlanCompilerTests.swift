import Testing
@testable import WheelBrowser

@Suite("WidgetPlanCompiler")
struct WidgetPlanCompilerTests {
    @Test("Compiler coerces multi-zone text plans into a list widget")
    func compilesMultiZoneClockPlan() throws {
        let plan = GeneratedWidgetPlan(
            title: "World Clock",
            widgetType: "text",
            source: GeneratedWidgetSourcePlan(
                kind: "currentDateTime",
                url: nil,
                jsonPath: nil,
                resultShape: nil,
                sortBy: nil,
                sortAscending: nil,
                limit: nil,
                timeZones: [
                    GeneratedWidgetTimeZonePlan(label: "Pacific", identifier: "America/Los_Angeles"),
                    GeneratedWidgetTimeZonePlan(label: "Beijing", identifier: "Asia/Shanghai"),
                ]
            ),
            refreshSeconds: 0,
            prompt: "Show Pacific and Beijing time",
            text: GeneratedWidgetTextPlan(
                contentField: nil,
                literalContent: nil,
                markdown: false,
                showTimeZone: true,
                includeSeconds: true
            ),
            metric: nil,
            list: GeneratedWidgetListPlan(
                variant: "compact",
                labelField: "ignored",
                valueField: nil,
                subtitleField: nil,
                badgeField: nil,
                captionField: nil,
                iconField: nil,
                linkField: nil,
                maxItems: nil
            ),
            table: nil,
            chart: nil
        )

        let manifest = try WidgetPlanCompiler.compile(plan, fallbackPrompt: "Fallback")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.count == 3)
        #expect(manifest.skillChain[0].skill == .currentDateTime)
        #expect(manifest.skillChain[1].skill == .currentDateTime)
        #expect(manifest.skillChain[2].skill == .transform)
        #expect(manifest.returns == "listData")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.variant == .compact)
    }

    @Test("Compiler creates a list manifest from a JSON API plan")
    func compilesJSONListPlan() throws {
        let plan = GeneratedWidgetPlan(
            title: "Top Coins",
            widgetType: "list",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: "https://example.com/coins.json",
                jsonPath: "$.items",
                resultShape: "collection",
                sortBy: "rank",
                sortAscending: true,
                limit: 5,
                timeZones: nil
            ),
            refreshSeconds: 300,
            prompt: "Show top coins",
            text: nil,
            metric: nil,
            list: GeneratedWidgetListPlan(
                variant: "ranked",
                labelField: "name",
                valueField: "price",
                subtitleField: "symbol",
                badgeField: "rank",
                captionField: nil,
                iconField: nil,
                linkField: "url",
                maxItems: 5
            ),
            table: nil,
            chart: nil
        )

        let manifest = try WidgetPlanCompiler.compile(plan, fallbackPrompt: "Fallback")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .transform])
        #expect(manifest.returns == "listData")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Top Coins")
        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.badgeField == "badge")
        #expect(config.linkField == "link")
        #expect(config.maxItems == 5)
        #expect(config.variant == .ranked)
    }

    @Test("Compiler infers list defaults for partial headline plans")
    func infersListDefaults() throws {
        let plan = GeneratedWidgetPlan(
            title: "Top Stories",
            widgetType: "list",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: "https://example.com/front-page.json",
                jsonPath: "$.items",
                resultShape: "collection",
                sortBy: "points",
                sortAscending: false,
                limit: 5,
                timeZones: nil
            ),
            refreshSeconds: 900,
            prompt: "Show the top stories",
            text: nil,
            metric: nil,
            list: nil,
            table: nil,
            chart: nil
        )

        let manifest = try WidgetPlanCompiler.compile(plan, fallbackPrompt: "Fallback")

        #expect(manifest.widgetType == .list)
        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .filterSort, .transform])

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Top Stories")
        #expect(config.labelField == "label")
        #expect(config.valueField == "value")
        #expect(config.subtitleField == "subtitle")
        #expect(config.linkField == "link")
        #expect(config.variant == .feed)
        #expect(config.maxItems == 5)
    }

    @Test("Compiler skips filterSort for single JSON widgets even when a limit is present")
    func skipsFilterSortForSingleShape() throws {
        let plan = GeneratedWidgetPlan(
            title: "FX",
            widgetType: "statCard",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: "https://example.com/fx.json",
                jsonPath: nil,
                resultShape: "single",
                sortBy: nil,
                sortAscending: nil,
                limit: 1,
                timeZones: nil
            ),
            refreshSeconds: 300,
            prompt: "Show FX",
            text: nil,
            metric: GeneratedWidgetMetricPlan(
                valueField: "rates.EUR",
                changeField: nil,
                changePercentField: nil,
                changeIsPercent: nil,
                prefix: nil,
                suffix: " EUR",
                footnote: nil
            ),
            list: nil,
            table: nil,
            chart: nil
        )

        let manifest = try WidgetPlanCompiler.compile(plan, fallbackPrompt: "Fallback")

        #expect(manifest.skillChain.map(\.skill) == [.fetchUrl, .parseJson, .transform])
    }

    @Test("Compiler rejects line charts without a y field or series")
    func rejectsIncompleteLineChartPlan() {
        let plan = GeneratedWidgetPlan(
            title: "Broken Chart",
            widgetType: "lineChart",
            source: GeneratedWidgetSourcePlan(
                kind: "jsonAPI",
                url: "https://example.com/chart.json",
                jsonPath: "$.points",
                resultShape: "collection",
                sortBy: nil,
                sortAscending: nil,
                limit: nil,
                timeZones: nil
            ),
            refreshSeconds: 300,
            prompt: "Show chart",
            text: nil,
            metric: nil,
            list: nil,
            table: nil,
            chart: GeneratedWidgetChartPlan(
                xField: "date",
                yField: nil,
                series: nil,
                color: nil,
                yPrefix: nil,
                yUnit: nil,
                showPoints: nil
            )
        )

        #expect(throws: WidgetPlanCompilationError.missingPlanSection("chart.series")) {
            try WidgetPlanCompiler.compile(plan, fallbackPrompt: "Fallback")
        }
    }
}
