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
