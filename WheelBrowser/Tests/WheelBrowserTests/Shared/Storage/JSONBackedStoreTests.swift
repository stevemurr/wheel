import Foundation
import Testing
@testable import WheelBrowser

@Suite("Store Layer", .serialized)
@MainActor
struct JSONBackedStoreTests {
    private struct SampleRecord: Codable, Equatable {
        let name: String
        let count: Int
        let createdAt: Date
    }

    @Test("Single-document stores round trip and delete")
    func singleDocumentRoundTrip() throws {
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let backend = FileSystemStoreBackend(rootURL: rootURL)
        let store = JSONBackedStore<SampleRecord>(
            backend: backend,
            namespace: "workspace",
            key: "record.json"
        )
        let record = SampleRecord(
            name: "Workspace",
            count: 3,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(try store.load() == nil)

        try store.save(record)

        #expect(try store.load() == record)

        try store.delete()

        #expect(try store.load() == nil)
    }

    @Test("Directory stores list keyed documents in sorted order")
    func directoryStoreListsAndDeletesKeys() throws {
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let backend = FileSystemStoreBackend(rootURL: rootURL)
        let store = JSONBackedDirectoryStore<SampleRecord>(
            backend: backend,
            namespace: "notes"
        )
        let first = SampleRecord(name: "A", count: 1, createdAt: .init(timeIntervalSince1970: 10))
        let second = SampleRecord(name: "B", count: 2, createdAt: .init(timeIntervalSince1970: 20))

        try store.save(second, for: "b.json")
        try store.save(first, for: "a.json")

        #expect(try store.keys().map(\.rawValue) == ["a.json", "b.json"])
        #expect(try store.load(key: "a.json") == first)
        #expect(try store.load(key: "b.json") == second)

        try store.delete(key: "a.json")

        #expect(try store.keys().map(\.rawValue) == ["b.json"])
        #expect(try store.load(key: "a.json") == nil)
    }

    @Test("Coding configuration applies ISO8601 and sorted pretty JSON")
    func codingConfigurationAppliesFormattingAndDates() throws {
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let backend = FileSystemStoreBackend(rootURL: rootURL)
        let store = JSONBackedStore<[String: Date]>(
            backend: backend,
            namespace: "history",
            key: "dates.json",
            codingConfiguration: .prettyPrintedSortedKeysISO8601
        )
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_000)

        try store.save([
            "zeta": expectedDate,
            "alpha": expectedDate,
        ])

        let rawData = try #require(try store.rawData())
        let rawJSON = String(decoding: rawData, as: UTF8.self)
        let alphaRange = try #require(rawJSON.range(of: "\"alpha\""))
        let zetaRange = try #require(rawJSON.range(of: "\"zeta\""))

        #expect(rawJSON.contains("\n"))
        #expect(alphaRange.lowerBound < zetaRange.lowerBound)
        #expect(rawJSON.contains("2023-11-14T22:13:20Z"))
        #expect(try store.load()?["alpha"] == expectedDate)
    }

    @Test("Missing documents return nil and empty directory listings")
    func missingDocumentsAreSafe() throws {
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let backend = FileSystemStoreBackend(rootURL: rootURL)
        let documentStore = JSONBackedStore<SampleRecord>(
            backend: backend,
            namespace: "workspace",
            key: "missing.json"
        )
        let directoryStore = JSONBackedDirectoryStore<SampleRecord>(
            backend: backend,
            namespace: "missing-directory"
        )

        #expect(try documentStore.load() == nil)
        #expect(try documentStore.rawData() == nil)
        #expect(try directoryStore.load(key: "missing.json") == nil)
        #expect(try directoryStore.keys().isEmpty)
    }

    @Test("Save scheduler coalesces pending writes and flushes latest state")
    func saveSchedulerCoalescesWrites() async {
        let scheduler = StoreSaveScheduler(delay: .milliseconds(50))
        var writes: [Int] = []

        scheduler.schedule {
            writes.append(1)
        }
        scheduler.schedule {
            writes.append(2)
        }

        try? await Task.sleep(for: .milliseconds(150))

        #expect(writes == [2])

        scheduler.flush {
            writes.append(3)
        }

        #expect(writes == [2, 3])
    }

    private func makeTemporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
