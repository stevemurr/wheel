import Foundation
import Testing
@testable import WheelBrowser

@Suite("SemanticSearchManagerV2", .serialized)
@MainActor
struct SemanticSearchManagerV2Tests {
    @Test("Queues and deduplicates indexing while backend initializes")
    func queuesIndexRequestsUntilBackendReady() async throws {
        let settings = AppSettings.shared
        let originalEnabled = settings.semanticSearchEnabled
        let originalVersion = settings.semanticSearchIndexVersion
        defer {
            settings.semanticSearchEnabled = originalEnabled
            settings.semanticSearchIndexVersion = originalVersion
        }

        settings.semanticSearchEnabled = true
        settings.semanticSearchIndexVersion = SemanticSearchManagerV2.currentIndexVersion

        let gate = AsyncGate()
        let backend = MockSemanticSearchBackend(
            gate: gate,
            stats: SemanticSearchBackendStats(pageCount: 0, chunkCount: 0)
        )

        let manager = SemanticSearchManagerV2(
            settings: settings,
            backendFactory: { backend },
            autoInitialize: true
        )

        await manager.indexPage(
            url: "https://example.com/queued",
            title: "Old Title",
            content: "old swift programming code"
        )
        await manager.indexPage(
            url: "https://example.com/queued",
            title: "New Title",
            content: "new swift programming code"
        )

        #expect(manager.pendingCount == 1)
        #expect(manager.stats.pendingCount == 1)

        await gate.open()
        try await waitUntil {
            manager.isAvailable && manager.pendingCount == 0 && manager.stats.pageCount == 1
        }

        let indexedDocuments = await backend.indexedDocuments()
        #expect(indexedDocuments.count == 1)
        #expect(indexedDocuments[0].title == "New Title")
        #expect(indexedDocuments[0].content == "new swift programming code")
        #expect(manager.stats.pendingCount == 0)
        #expect(manager.stats.available)
    }

    @Test("Index migration clears native search storage without touching reading list database")
    func migrationClearsOnlyNativeSemanticIndex() async throws {
        let settings = AppSettings.shared
        let originalEnabled = settings.semanticSearchEnabled
        let originalVersion = settings.semanticSearchIndexVersion
        defer {
            settings.semanticSearchEnabled = originalEnabled
            settings.semanticSearchIndexVersion = originalVersion
        }

        settings.semanticSearchEnabled = true
        settings.semanticSearchIndexVersion = SemanticSearchManagerV2.currentIndexVersion - 1

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let backend = NativeSearchService(
            dbPath: tempDir.appendingPathComponent("meta.db"),
            embedder: MockVecturaEmbedder()
        )
        try await backend.indexPage(
            url: URL(string: "https://example.com/swift")!,
            title: "Swift Doc",
            content: "Swift programming code for local search migration verification.",
            categories: [.web]
        )
        let statsBeforeMigration = try await backend.getStats()
        #expect(statsBeforeMigration.pageCount == 1)
        #expect(statsBeforeMigration.chunkCount > 0)

        let readingListDB = try SearchDatabase(
            dbPath: tempDir.appendingPathComponent("semantic_search.db")
        )
        try await readingListDB.initialize()
        _ = try await readingListDB.upsertPage(
            url: URL(string: "https://example.com/saved")!,
            title: "Saved Page"
        )
        let isSaved = try await readingListDB.toggleSaved(
            url: "https://example.com/saved",
            title: "Saved Page"
        )
        #expect(isSaved)

        let manager = SemanticSearchManagerV2(
            settings: settings,
            backendFactory: { backend },
            autoInitialize: true
        )

        try await waitUntil {
            manager.isAvailable && manager.stats.pageCount == 0 && manager.stats.chunkCount == 0
        }

        let statsAfterMigration = try await backend.getStats()
        #expect(statsAfterMigration.pageCount == 0)
        #expect(statsAfterMigration.chunkCount == 0)

        let savedPages = try await readingListDB.getSavedPages()
        #expect(savedPages.count == 1)
        #expect(settings.semanticSearchIndexVersion == SemanticSearchManagerV2.currentIndexVersion)

        await readingListDB.close()
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        interval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: interval)
        }

        Issue.record("Timed out waiting for condition")
        #expect(Bool(false))
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }
}

private actor MockSemanticSearchBackend: SemanticSearchBackend {
    struct IndexedDocument: Equatable {
        let url: String
        let title: String?
        let content: String
    }

    private let gate: AsyncGate?
    private var statsValue: SemanticSearchBackendStats
    private var indexedDocumentValues: [IndexedDocument] = []
    private var clearAllInvocations = 0

    init(gate: AsyncGate? = nil, stats: SemanticSearchBackendStats) {
        self.gate = gate
        self.statsValue = stats
    }

    func validateBackend() async throws {
        await gate?.wait()
    }

    func indexPage(
        url: URL,
        title: String?,
        content: String,
        categories: Set<EmbeddingCategory>
    ) async throws {
        indexedDocumentValues.append(
            IndexedDocument(
                url: url.absoluteString,
                title: title,
                content: content
            )
        )
        statsValue = SemanticSearchBackendStats(
            pageCount: indexedDocumentValues.count,
            chunkCount: indexedDocumentValues.count
        )
        _ = categories
    }

    func search(
        query: String,
        categories: Set<EmbeddingCategory>?,
        limit: Int
    ) async throws -> [NativeSearchResult] {
        _ = query
        _ = categories
        _ = limit
        return []
    }

    func getStats() async throws -> SemanticSearchBackendStats {
        statsValue
    }

    func clearAll() async throws {
        clearAllInvocations += 1
        indexedDocumentValues.removeAll()
        statsValue = SemanticSearchBackendStats(pageCount: 0, chunkCount: 0)
    }

    func indexedDocuments() -> [IndexedDocument] {
        indexedDocumentValues
    }

    func clearAllCallCount() -> Int {
        clearAllInvocations
    }
}
