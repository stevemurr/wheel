import Foundation
import SwiftUI

/// Manages semantic search using native on-device embeddings and hybrid search
@MainActor
@Observable
class SemanticSearchManagerV2 {
    static let currentIndexVersion = 2
    static let shared = SemanticSearchManagerV2()
    nonisolated private static let initializationTimeout: TimeInterval = 20
    nonisolated private static let indexingTimeout: TimeInterval = 20
    nonisolated private static let searchTimeout: TimeInterval = 10
    nonisolated private static let statsTimeout: TimeInterval = 5

    private(set) var isIndexing = false
    private(set) var pendingCount: Int = 0
    private(set) var stats: SemanticSearchStats = .empty
    private(set) var lastError: String?
    private(set) var isAvailable = false

    @ObservationIgnored private let backendFactory: @Sendable () -> any SemanticSearchBackend
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var searchService: (any SemanticSearchBackend)?
    @ObservationIgnored private var initializationTask: Task<any SemanticSearchBackend, Error>?
    @ObservationIgnored private var pendingIndexRequests: [String: PendingIndexRequest] = [:]
    @ObservationIgnored private var pendingSequence: UInt64 = 0

    init(
        settings: AppSettings = .shared,
        backendFactory: @escaping @Sendable () -> any SemanticSearchBackend = { NativeSearchService() },
        autoInitialize: Bool = true
    ) {
        self.settings = settings
        self.backendFactory = backendFactory

        if autoInitialize {
            Task {
                await initialize()
            }
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        Log.Search.debug("SemanticSearchManagerV2 initializing (native mode)")

        guard settings.semanticSearchEnabled else {
            initializationTask?.cancel()
            initializationTask = nil
            Log.Search.info("Semantic search disabled in settings")
            searchService = nil
            isAvailable = false
            lastError = nil
            clearPendingIndexRequests()
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            return
        }

        if let searchService {
            self.searchService = searchService
            isAvailable = true
            lastError = nil
            updateStatsSnapshot(available: true)
            await updateStats()
            return
        }

        if initializationTask == nil {
            Log.Search.debug("SemanticSearchManagerV2 starting backend initialization off-main")
            let backend = backendFactory()
            initializationTask = Task.detached(priority: .utility) { () throws -> any SemanticSearchBackend in
                try await withSemanticSearchTimeout(seconds: Self.initializationTimeout) {
                    try await backend.validateBackend()
                }
                return backend
            }
        }

        do {
            guard let initializationTask else { return }
            let backend = try await initializationTask.value
            self.initializationTask = nil
            try await applyIndexMigrationIfNeeded(using: backend)
            searchService = backend
            isAvailable = true
            lastError = nil
            updateStatsSnapshot(available: true)
            Log.Search.info("Native search service initialized")
            await drainPendingIndexRequests(using: backend)
            await updateStats()
        } catch is CancellationError {
            self.initializationTask = nil
            Log.Search.debug("Semantic search initialization cancelled")
        } catch {
            self.initializationTask = nil
            searchService = nil
            isAvailable = false
            lastError = "Semantic search embeddings model failed to load. Re-download the local model cache to re-enable semantic search."
            clearPendingIndexRequests()
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            Log.Search.error("Native search service unavailable: \(error.localizedDescription)")
        }
    }

    /// Reinitialize with new settings
    func reinitialize() async {
        initializationTask?.cancel()
        initializationTask = nil
        searchService = nil
        isAvailable = false
        lastError = nil
        clearPendingIndexRequests()
        updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
        await initialize()
    }

    // MARK: - Indexing

    /// Index a page for semantic search
    func indexPage(
        url: String,
        title: String,
        content: String,
        workspaceID: UUID? = nil,
        categories: Set<EmbeddingCategory> = [.history, .web]
    ) async {
        Log.Search.debug("indexPage called: url=\(url), title=\(title), contentLength=\(content.count)")

        guard settings.semanticSearchEnabled else {
            Log.Search.debug("indexPage skipped: semantic search disabled")
            return
        }
        guard let pageURL = URL(string: url) else {
            Log.Search.debug("indexPage skipped: invalid URL '\(url)'")
            return
        }

        let request = PendingIndexRequest(
            url: pageURL,
            title: title,
            content: content,
            workspaceID: workspaceID,
            categories: categories,
            sequence: nextPendingSequence()
        )

        if let service = searchService, isAvailable {
            await performIndexRequest(request, using: service)
            return
        }

        if initializationTask != nil {
            enqueuePendingIndexRequest(request)
            return
        }

        guard lastError == nil else {
            Log.Search.debug("indexPage skipped: semantic search unavailable with existing error")
            return
        }

        enqueuePendingIndexRequest(request)
        Task {
            await initialize()
        }
    }

    /// Register a page without content extraction (for PDFs and other non-indexable content)
    func registerPage(url: String, title: String, workspaceID: UUID? = nil) async {
        // No-op — PDFs need content extraction to be indexed
    }

    // MARK: - Search

    /// Search for pages semantically similar to the query
    func search(query: String, limit: Int = 20) async -> [SemanticSearchResult] {
        Log.Search.debug("search called: query='\(query)', limit=\(limit)")

        guard isAvailable, let service = searchService else {
            Log.Search.debug("search skipped: isAvailable=\(isAvailable)")
            return []
        }

        do {
            let results = try await withSemanticSearchTimeout(seconds: Self.searchTimeout) {
                try await service.search(query: query, categories: nil, limit: limit)
            }
            Log.Search.debug("search completed: \(results.count) results for '\(query)'")
            return results.map { makeResult(from: $0) }
        } catch SemanticSearchOperationTimeout.timedOut {
            searchService = nil
            isAvailable = false
            lastError = "Semantic search timed out and has been disabled to keep the app responsive."
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            Log.Search.error("Search timeout for '\(query)'; disabling semantic search")
            return []
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                Log.Search.debug("Search cancelled (superseded by newer query)")
            } else {
                lastError = error.localizedDescription
                Log.Search.error("Search error: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// Search with category filtering
    func searchWithCategories(
        query: String,
        categories: Set<EmbeddingCategory>,
        limit: Int = 20
    ) async -> [SemanticSearchResult] {
        Log.Search.debug("searchWithCategories called: query='\(query)', categories=\(categories.map { $0.rawValue }), limit=\(limit)")

        guard isAvailable, let service = searchService else {
            Log.Search.debug("searchWithCategories skipped: isAvailable=\(isAvailable)")
            return []
        }

        do {
            let results = try await withSemanticSearchTimeout(seconds: Self.searchTimeout) {
                try await service.search(query: query, categories: categories.isEmpty ? nil : categories, limit: limit)
            }
            Log.Search.debug("searchWithCategories completed: \(results.count) results for '\(query)'")
            return results.map { makeResult(from: $0) }
        } catch SemanticSearchOperationTimeout.timedOut {
            searchService = nil
            isAvailable = false
            lastError = "Semantic search timed out and has been disabled to keep the app responsive."
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            Log.Search.error("Category search timeout for '\(query)'; disabling semantic search")
            return []
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                Log.Search.debug("Category search cancelled (superseded by newer query)")
            } else {
                lastError = error.localizedDescription
                Log.Search.error("Search error: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// Convert a NativeSearchResult to a SemanticSearchResult
    private func makeResult(from item: NativeSearchResult) -> SemanticSearchResult {
        let id = UInt64(bitPattern: Int64(item.url.hashValue))
        let citation = CitationInfo(
            content: item.content,
            snippet: item.snippet,
            sectionHierarchy: item.sectionHierarchy,
            matchedBy: item.matchedBy,
            positionInDoc: item.positionInDoc,
            chunkScore: item.chunkRelevanceScore
        )
        let additionalCitations = item.additionalChunks.map { chunk in
            CitationInfo(
                content: chunk.content,
                snippet: chunk.snippet,
                sectionHierarchy: chunk.sectionHierarchy,
                matchedBy: chunk.matchedBy,
                positionInDoc: chunk.positionInDoc,
                chunkScore: chunk.relevanceScore
            )
        }
        let matchedBy = Set(item.matchedBy)
        return SemanticSearchResult(
            id: id,
            page: IndexedPage(
                id: id,
                url: item.url,
                title: item.title ?? "",
                snippet: item.snippet ?? String(item.content.prefix(200)),
                timestamp: Date(),
                workspaceID: nil,
                citation: citation,
                additionalCitations: additionalCitations,
                documentMatchedBy: matchedBy
            ),
            score: item.score
        )
    }

    // MARK: - Stats

    private func updateStats() async {
        guard let service = searchService else {
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: isAvailable)
            return
        }

        do {
            let stats = try await withSemanticSearchTimeout(seconds: Self.statsTimeout) {
                try await service.getStats()
            }
            updateStatsSnapshot(pageCount: stats.pageCount, chunkCount: stats.chunkCount, available: true)
        } catch SemanticSearchOperationTimeout.timedOut {
            searchService = nil
            isAvailable = false
            lastError = "Semantic search timed out while refreshing stats. It has been disabled to keep the app responsive."
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            Log.Search.error("Semantic search stats timed out; disabling semantic search")
        } catch {
            Log.Search.warning("Failed to get stats: \(error.localizedDescription)")
        }
    }

    /// Refresh index statistics
    func refreshStats() async {
        await updateStats()
    }

    // MARK: - Maintenance

    /// Clear all entries from the index
    func clearIndex() async {
        guard let service = searchService else {
            Log.Search.debug("clearIndex skipped: service not available")
            return
        }

        do {
            try await withSemanticSearchTimeout(seconds: Self.indexingTimeout) {
                try await service.clearAll()
            }
            await updateStats()
            Log.Search.info("Index cleared successfully")
        } catch SemanticSearchOperationTimeout.timedOut {
            searchService = nil
            isAvailable = false
            lastError = "Semantic search timed out while clearing the index. It has been disabled to keep the app responsive."
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            Log.Search.error("Semantic search clearIndex timed out; disabling semantic search")
        } catch {
            lastError = error.localizedDescription
            Log.Search.error("Failed to clear index: \(error.localizedDescription)")
        }
    }

    /// Save/sync the index (called on app termination)
    func save() async {
        // No-op — SQLite handles persistence via WAL
    }

    private struct PendingIndexRequest {
        let url: URL
        let title: String
        let content: String
        let workspaceID: UUID?
        let categories: Set<EmbeddingCategory>
        let sequence: UInt64
    }

    private func nextPendingSequence() -> UInt64 {
        pendingSequence += 1
        return pendingSequence
    }

    private func enqueuePendingIndexRequest(_ request: PendingIndexRequest) {
        pendingIndexRequests[request.url.absoluteString] = request
        pendingCount = pendingIndexRequests.count
        updateStatsSnapshot(pendingCount: pendingCount)
        Log.Search.debug("Queued semantic index request for \(request.url.absoluteString); pending=\(pendingCount)")
    }

    private func clearPendingIndexRequests() {
        pendingIndexRequests.removeAll()
        pendingCount = 0
        updateStatsSnapshot(pendingCount: 0)
    }

    private func drainPendingIndexRequests(using backend: any SemanticSearchBackend) async {
        guard !pendingIndexRequests.isEmpty else { return }

        let pendingRequests = pendingIndexRequests.values.sorted { $0.sequence < $1.sequence }
        pendingIndexRequests.removeAll()
        pendingCount = 0
        updateStatsSnapshot(pendingCount: 0)
        isIndexing = true
        defer { isIndexing = false }

        for request in pendingRequests {
            do {
                try await withSemanticSearchTimeout(seconds: Self.indexingTimeout) {
                    try await backend.indexPage(
                        url: request.url,
                        title: request.title,
                        content: request.content,
                        categories: request.categories
                    )
                }
                Log.Search.info("Successfully indexed queued page: \(request.url.absoluteString)")
            } catch SemanticSearchOperationTimeout.timedOut {
                searchService = nil
                isAvailable = false
                lastError = "Semantic search timed out while indexing. It has been disabled to keep the app responsive."
                updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
                Log.Search.error("Queued indexing timeout for \(request.url.absoluteString); disabling semantic search")
                break
            } catch {
                lastError = error.localizedDescription
                Log.Search.error("Queued indexing error for \(request.url.absoluteString): \(error.localizedDescription)")
            }
        }
    }

    private func performIndexRequest(
        _ request: PendingIndexRequest,
        using backend: any SemanticSearchBackend
    ) async {
        isIndexing = true
        defer { isIndexing = false }

        do {
            try await withSemanticSearchTimeout(seconds: Self.indexingTimeout) {
                try await backend.indexPage(
                    url: request.url,
                    title: request.title,
                    content: request.content,
                    categories: request.categories
                )
            }
            Log.Search.info("Successfully indexed: \(request.url.absoluteString) (content: \(request.content.count) chars)")
            await updateStats()
        } catch SemanticSearchOperationTimeout.timedOut {
            searchService = nil
            isAvailable = false
            lastError = "Semantic search timed out while indexing. It has been disabled to keep the app responsive."
            updateStatsSnapshot(pageCount: 0, chunkCount: 0, available: false)
            Log.Search.error("Indexing timeout for \(request.url.absoluteString); disabling semantic search")
        } catch {
            lastError = error.localizedDescription
            Log.Search.error("Indexing error for \(request.url.absoluteString): \(error.localizedDescription)")
        }
    }

    private func applyIndexMigrationIfNeeded(using backend: any SemanticSearchBackend) async throws {
        guard settings.semanticSearchIndexVersion < Self.currentIndexVersion else { return }

        Log.Search.info(
            "Clearing native semantic index for version upgrade \(settings.semanticSearchIndexVersion) -> \(Self.currentIndexVersion)"
        )
        try await withSemanticSearchTimeout(seconds: Self.indexingTimeout) {
            try await backend.clearAll()
        }
        settings.semanticSearchIndexVersion = Self.currentIndexVersion
    }

    private func updateStatsSnapshot(
        pageCount: Int? = nil,
        chunkCount: Int? = nil,
        pendingCount: Int? = nil,
        available: Bool? = nil
    ) {
        stats = SemanticSearchStats(
            pageCount: pageCount ?? stats.pageCount,
            chunkCount: chunkCount ?? stats.chunkCount,
            pendingCount: pendingCount ?? self.pendingCount,
            available: available ?? isAvailable
        )
    }
}

// MARK: - Bridge for existing code

extension SemanticSearchManagerV2 {
    @MainActor
    static var current: SemanticSearchManagerV2 {
        shared
    }
}

private enum SemanticSearchOperationTimeout: Error {
    case timedOut
}

private func withSemanticSearchTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SemanticSearchOperationTimeout.timedOut
        }

        let result = try await group.next()
        group.cancelAll()

        guard let result else {
            throw SemanticSearchOperationTimeout.timedOut
        }
        return result
    }
}

// MARK: - Result Types

/// Citation information from a matching chunk
struct CitationInfo {
    let content: String
    let snippet: String?
    let sectionHierarchy: [String]
    let matchedBy: [String]
    let positionInDoc: Float
    let chunkScore: Float

    init(
        content: String,
        snippet: String? = nil,
        sectionHierarchy: [String] = [],
        matchedBy: [String] = [],
        positionInDoc: Float = 0.0,
        chunkScore: Float = 0.0
    ) {
        self.content = content
        self.snippet = snippet
        self.sectionHierarchy = sectionHierarchy
        self.matchedBy = matchedBy
        self.positionInDoc = positionInDoc
        self.chunkScore = chunkScore
    }
}

/// A semantic search result
struct SemanticSearchResult: Identifiable {
    let id: UInt64
    let page: IndexedPage
    let score: Float
}

/// An indexed page
struct IndexedPage: Identifiable {
    let id: UInt64
    let url: String
    let title: String
    let snippet: String
    let timestamp: Date
    let workspaceID: UUID?
    let citation: CitationInfo?
    let additionalCitations: [CitationInfo]
    let documentMatchedBy: Set<String>

    init(
        id: UInt64,
        url: String,
        title: String,
        snippet: String,
        timestamp: Date,
        workspaceID: UUID?,
        citation: CitationInfo? = nil,
        additionalCitations: [CitationInfo] = [],
        documentMatchedBy: Set<String> = []
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.snippet = snippet
        self.timestamp = timestamp
        self.workspaceID = workspaceID
        self.citation = citation
        self.additionalCitations = additionalCitations
        self.documentMatchedBy = documentMatchedBy
    }
}
