import Foundation
import Testing
@testable import WheelBrowser

@Suite("WidgetDashboardStore")
struct WidgetDashboardStoreTests {
    @MainActor
    @Test("Store persists widgets and order")
    func persistsWidgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        let first = textManifest(title: "First", content: "Hello")
        let second = textManifest(title: "Second", content: "World")

        try store.add(manifest: first)
        try store.add(manifest: second)
        store.move(from: 1, to: 0)

        let reloaded = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )

        #expect(reloaded.records.count == 2)
        #expect(reloaded.records[0].manifest.id == second.id)
        #expect(reloaded.records[1].manifest.id == first.id)
    }

    @MainActor
    @Test("Store persists widget layout preferences")
    func persistsLayoutPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        let manifest = textManifest(title: "Wide", content: "Focus")

        try store.add(manifest: manifest)
        store.toggleLayoutPreference(id: manifest.id)

        let reloaded = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )

        #expect(reloaded.records.count == 1)
        #expect(reloaded.records[0].layoutPreference == .singleColumn)
    }

    @MainActor
    @Test("Store cycles widget layout preferences")
    func cyclesLayoutPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        let manifest = textManifest(title: "Wide", content: "Focus")

        try store.add(manifest: manifest)
        #expect(store.records[0].layoutPreference == .auto)

        store.toggleLayoutPreference(id: manifest.id)
        #expect(store.records[0].layoutPreference == .singleColumn)

        store.toggleLayoutPreference(id: manifest.id)
        #expect(store.records[0].layoutPreference == .fullWidth)

        store.toggleLayoutPreference(id: manifest.id)
        #expect(store.records[0].layoutPreference == .auto)
    }

    @MainActor
    @Test("Store persists widget visualization preferences")
    func persistsVisualizationPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        let manifest = lineChartManifest(title: "BTC Price (30D)")

        try store.add(manifest: manifest)
        store.toggleVisualizationPreference(id: manifest.id)

        let reloaded = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )

        #expect(reloaded.records.count == 1)
        #expect(reloaded.records[0].visualizationPreference == .value)
    }

    @MainActor
    @Test("Store cycles widget visualization preferences for line charts")
    func cyclesVisualizationPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        let manifest = lineChartManifest(title: "BTC Price (30D)")

        try store.add(manifest: manifest)
        #expect(store.records[0].visualizationPreference == .auto)

        store.toggleVisualizationPreference(id: manifest.id)
        #expect(store.records[0].visualizationPreference == .value)

        store.toggleVisualizationPreference(id: manifest.id)
        #expect(store.records[0].visualizationPreference == .lineChart)

        store.toggleVisualizationPreference(id: manifest.id)
        #expect(store.records[0].visualizationPreference == .value)
    }

    @MainActor
    @Test("Store marks stale widgets for refresh")
    func marksStaleWidgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")
        let staleManifest = textManifest(title: "Stale", content: "Old", ttl: 60)
        let records = [
            WidgetRecord(
                manifest: staleManifest,
                position: 0,
                lastAttemptedAt: Date(timeIntervalSinceNow: -300),
                lastLoadedAt: Date(timeIntervalSinceNow: -300),
                lastError: nil
            ),
        ]
        let encoder = JSONEncoder()
        try encoder.encode(records).write(to: storageURL)

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        store.refreshStale()

        #expect(store.pendingRefreshIDs == [staleManifest.id])
    }

    @MainActor
    @Test("Store hard resets legacy files")
    func hardResetsLegacyFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storageURL = directory.appendingPathComponent("widgets.json")
        let legacyFile = directory.appendingPathComponent("pipeline_widgets.json")
        let legacyDirectory = directory.appendingPathComponent("modules")
        try Data("legacy".utf8).write(to: legacyFile)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        _ = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [legacyFile, legacyDirectory],
            observeActivation: false
        )

        #expect(!FileManager.default.fileExists(atPath: legacyFile.path))
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    @MainActor
    @Test("Recent widget errors do not immediately retrigger stale refresh")
    func recentErrorDoesNotImmediatelyRefresh() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")
        let manifest = textManifest(title: "Retry", content: "Later", ttl: 300)
        let records = [
            WidgetRecord(
                manifest: manifest,
                position: 0,
                lastAttemptedAt: Date(),
                lastLoadedAt: nil,
                lastError: "Network error"
            ),
        ]

        let encoder = JSONEncoder()
        try encoder.encode(records).write(to: storageURL)

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )
        store.refreshStale()

        #expect(store.pendingRefreshIDs.isEmpty)
    }

    @MainActor
    @Test("Store repairs malformed Reddit widgets while loading persisted state")
    func repairsPersistedRedditWidgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")
        let manifest = malformedRedditManifest()
        let records = [
            WidgetRecord(
                manifest: manifest,
                position: 0,
                lastAttemptedAt: nil,
                lastLoadedAt: nil,
                lastError: nil
            ),
        ]

        let encoder = JSONEncoder()
        try encoder.encode(records).write(to: storageURL)

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )

        #expect(store.records.count == 1)
        #expect(store.records[0].manifest.skillChain[0].params["url"]?.stringValue?.contains("raw_json=1") == true)
        #expect(store.records[0].manifest.skillChain[0].params["url"]?.stringValue?.contains("t=day") == true)
        #expect(store.records[0].manifest.skillChain[2].params["sortBy"]?.stringValue == "data.score")

        let mapping = store.records[0].manifest.skillChain[3].params["mapping"]?.dictionaryValue
        #expect(mapping?["label"] as? String == "data.title")
        #expect(mapping?["value"] as? String == "data.score")
    }

    @MainActor
    @Test("Store repairs persisted Pocket Portfolio history path")
    func repairsPersistedPocketPortfolioWidgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")
        let manifest = legacyPocketPortfolioManifest()
        let records = [
            WidgetRecord(
                manifest: manifest,
                position: 0,
                lastAttemptedAt: nil,
                lastLoadedAt: nil,
                lastError: nil
            ),
        ]

        let encoder = JSONEncoder()
        try encoder.encode(records).write(to: storageURL)

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )

        #expect(store.records.count == 1)
        #expect(store.records[0].manifest.skillChain[1].params["path"]?.stringValue == "data")
    }

    @MainActor
    @Test("Store repairs persisted Pocket Portfolio candle data path")
    func repairsPersistedPocketPortfolioCandleDataWidgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("widgets.json")
        let manifest = legacyPocketPortfolioManifest(path: "data.candle_data")
        let records = [
            WidgetRecord(
                manifest: manifest,
                position: 0,
                lastAttemptedAt: nil,
                lastLoadedAt: nil,
                lastError: nil
            ),
        ]

        let encoder = JSONEncoder()
        try encoder.encode(records).write(to: storageURL)

        let store = WidgetDashboardStore(
            storageURL: storageURL,
            legacyCleanupPaths: [],
            observeActivation: false
        )

        #expect(store.records.count == 1)
        #expect(store.records[0].manifest.skillChain[1].params["path"]?.stringValue == "data")
    }
}

private func textManifest(title: String, content: String, ttl: Int = 300) -> WidgetManifest {
    WidgetManifest(
        widgetType: .text,
        config: .text(TextConfig(title: title, markdown: false)),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .transform,
                params: [
                    "data": AnyCodable(["content": content]),
                    "mapping": AnyCodable(["content": "content"]),
                ],
                outputKey: "textData"
            ),
        ],
        returns: "textData",
        ttl: ttl,
        prompt: title
    )
}

private func malformedRedditManifest() -> WidgetManifest {
    WidgetManifest(
        widgetType: .list,
        config: .list(
            ListConfig(
                title: "Top 5 Posts in Swift Subreddit",
                labelField: "label",
                valueField: "value",
                subtitleField: nil,
                badgeField: nil,
                captionField: nil,
                iconField: nil,
                linkField: nil,
                maxItems: 5,
                variant: .ranked
            )
        ),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .fetchUrl,
                params: [
                    "url": AnyCodable("https://www.reddit.com/r/swift/top.json?limit=5"),
                ],
                outputKey: "raw"
            ),
            WidgetSkillStep(
                step: 2,
                skill: .parseJson,
                params: [
                    "json": AnyCodable("$raw"),
                    "path": AnyCodable("data.children"),
                ],
                outputKey: "sourceData"
            ),
            WidgetSkillStep(
                step: 3,
                skill: .filterSort,
                params: [
                    "data": AnyCodable("$sourceData"),
                    "sortBy": AnyCodable("score"),
                    "ascending": AnyCodable(false),
                    "limit": AnyCodable(5),
                ],
                outputKey: "filteredData"
            ),
            WidgetSkillStep(
                step: 4,
                skill: .transform,
                params: [
                    "data": AnyCodable("$filteredData"),
                    "mapping": AnyCodable([
                        "label": "title",
                        "value": "score",
                    ]),
                ],
                outputKey: "listData"
            ),
        ],
        returns: "listData",
        ttl: 60,
        prompt: "give me a list of the top 5 posts in the swift subbreddit"
    )
}

private func legacyPocketPortfolioManifest(path: String = "history_sample") -> WidgetManifest {
    WidgetManifest(
        widgetType: .lineChart,
        config: .lineChart(
            LineChartConfig(
                title: "AMD Price (30D)",
                xField: "date",
                series: [
                    LineChartSeries(field: "close", label: "AMD", color: "#ff6b35"),
                ],
                yPrefix: "$",
                showPoints: false
            )
        ),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .fetchUrl,
                params: [
                    "url": AnyCodable("https://www.pocketportfolio.app/api/tickers/AMD/json"),
                ],
                outputKey: "raw"
            ),
            WidgetSkillStep(
                step: 2,
                skill: .parseJson,
                params: [
                    "json": AnyCodable("$raw"),
                    "path": AnyCodable(path),
                ],
                outputKey: "history"
            ),
        ],
        returns: "history",
        ttl: 1800,
        prompt: "AMD trend sample"
    )
}

private func lineChartManifest(title: String) -> WidgetManifest {
    WidgetManifest(
        widgetType: .lineChart,
        config: .lineChart(
            LineChartConfig(
                title: title,
                xField: "date",
                series: [
                    LineChartSeries(field: "price", label: "BTC", color: "#f7931a"),
                ],
                yPrefix: "$",
                showPoints: true
            )
        ),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .transform,
                params: [
                    "data": AnyCodable([
                        ["date": "3/1", "price": 62_100.0],
                        ["date": "3/2", "price": 63_450.0],
                    ]),
                    "mapping": AnyCodable([
                        "date": "date",
                        "price": "price",
                    ]),
                ],
                outputKey: "chartData"
            ),
        ],
        returns: "chartData",
        ttl: 300,
        prompt: title
    )
}
