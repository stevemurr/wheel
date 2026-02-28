import Foundation
import SwiftUI
import Combine

/// Manages semantic search using remote DIndex server
@MainActor
class SemanticSearchManagerV2: ObservableObject {
    static let shared = SemanticSearchManagerV2()

    @Published private(set) var isIndexing = false
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isAvailable = false
    @Published private(set) var isDIndexConnected = false

    private var dindexService: DIndexService?

    /// Public accessor for the DIndex service (used by ScrapeManager)
    var dIndexService: DIndexService? {
        dindexService
    }

    private var settings: AppSettings { AppSettings.shared }
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Listen for settings changes
        NotificationCenter.default.publisher(for: .embeddingSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    await self.reinitialize()
                }
            }
            .store(in: &cancellables)

        Task {
            await initialize()
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        Log.Search.debug("SemanticSearchManagerV2 initializing, dindexEnabled=\(settings.dindexEnabled)")
        guard settings.dindexEnabled else {
            Log.Search.info("DIndex disabled in settings, skipping initialization")
            isAvailable = false
            isDIndexConnected = false
            return
        }

        await initializeDIndex()
    }

    /// Initialize remote DIndex service
    private func initializeDIndex() async {
        Log.Search.debug("initializeDIndex starting, endpoint=\(settings.dindexEndpoint)")
        guard settings.dindexEnabled,
              let endpoint = URL(string: settings.dindexEndpoint) else {
            Log.Search.warning("initializeDIndex failed: dindexEnabled=\(settings.dindexEnabled), endpoint invalid: '\(settings.dindexEndpoint)'")
            dindexService = nil
            isDIndexConnected = false
            isAvailable = false
            return
        }

        let apiKey = settings.dindexAPIKey.isEmpty ? nil : settings.dindexAPIKey
        Log.Search.debug("Creating DIndexService with endpoint=\(endpoint), apiKey=\(apiKey != nil ? "set" : "nil")")
        let service = DIndexService(endpoint: endpoint, apiKey: apiKey)

        // Verify connection
        Log.Search.debug("Checking DIndex health...")
        let healthy = await service.checkHealth()
        if healthy {
            dindexService = service
            isDIndexConnected = true
            isAvailable = true
            lastError = nil
            Log.Search.info("DIndex connected at \(settings.dindexEndpoint)")

            // Fetch initial stats
            await updateStats()
        } else {
            dindexService = nil
            isDIndexConnected = false
            isAvailable = false
            lastError = "Could not connect to DIndex server"
            Log.Search.warning("DIndex health check failed for \(settings.dindexEndpoint)")
        }
    }

    /// Reinitialize with new settings
    func reinitialize() async {
        dindexService = nil
        isDIndexConnected = false
        isAvailable = false
        lastError = nil

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
        Log.Search.debug("indexPage called: url=\(url), title=\(title), contentLength=\(content.count), categories=\(categories.map { $0.rawValue })")

        guard isAvailable, let dindex = dindexService else {
            Log.Search.debug("indexPage skipped: isAvailable=\(isAvailable), dindexService=\(dindexService != nil ? "present" : "nil")")
            return
        }
        guard let pageURL = URL(string: url) else {
            Log.Search.debug("indexPage skipped: invalid URL '\(url)'")
            return
        }

        isIndexing = true
        defer { isIndexing = false }

        do {
            Log.Search.debug("Sending to DIndex: \(pageURL.absoluteString)")
            try await dindex.indexPage(
                url: pageURL,
                title: title,
                content: content,
                categories: categories
            )
            Log.Search.info("Successfully indexed: \(url) (content: \(content.count) chars)")
            await updateStats()
        } catch {
            lastError = error.localizedDescription
            Log.Search.error("Indexing error for \(url): \(error.localizedDescription)")
        }
    }

    /// Register a page without content extraction (for PDFs and other non-indexable content)
    func registerPage(url: String, title: String, workspaceID: UUID? = nil) async {
        // No-op for DIndex-only mode - pages are indexed with content
    }

    // MARK: - Search

    /// Search for pages semantically similar to the query
    func search(query: String, limit: Int = 20) async -> [SemanticSearchResult] {
        Log.Search.debug("search called: query='\(query)', limit=\(limit)")

        guard isAvailable, let dindex = dindexService else {
            Log.Search.debug("search skipped: isAvailable=\(isAvailable), dindexService=\(dindexService != nil ? "present" : "nil")")
            return []
        }

        do {
            let results = try await dindex.search(query: query, limit: limit)
            Log.Search.debug("search completed: \(results.count) results for '\(query)'")
            return results.map { item in
                let hashValue = item.id.hashValue
                let id = UInt64(bitPattern: Int64(hashValue))
                let citation = CitationInfo(
                    content: item.content,
                    sectionHierarchy: item.sectionHierarchy,
                    matchedBy: item.matchedBy,
                    positionInDoc: item.positionInDoc,
                    chunkScore: item.chunkRelevanceScore
                )
                return SemanticSearchResult(
                    id: id,
                    page: IndexedPage(
                        id: id,
                        url: item.url ?? "",
                        title: item.title ?? "",
                        snippet: item.snippet ?? String(item.content.prefix(200)),
                        timestamp: Date(),
                        workspaceID: nil,
                        citation: citation
                    ),
                    score: item.score
                )
            }
        } catch {
            // Cancellation is expected during debounced typing - log as debug, not error
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

        guard isAvailable, let dindex = dindexService else {
            Log.Search.debug("searchWithCategories skipped: isAvailable=\(isAvailable), dindexService=\(dindexService != nil ? "present" : "nil")")
            return []
        }

        do {
            let results = try await dindex.search(
                query: query,
                categories: categories.isEmpty ? nil : categories,
                limit: limit
            )
            Log.Search.debug("searchWithCategories completed: \(results.count) results for '\(query)'")
            return results.map { item in
                let hashValue = item.id.hashValue
                let id = UInt64(bitPattern: Int64(hashValue))
                let citation = CitationInfo(
                    content: item.content,
                    sectionHierarchy: item.sectionHierarchy,
                    matchedBy: item.matchedBy,
                    positionInDoc: item.positionInDoc,
                    chunkScore: item.chunkRelevanceScore
                )
                return SemanticSearchResult(
                    id: id,
                    page: IndexedPage(
                        id: id,
                        url: item.url ?? "",
                        title: item.title ?? "",
                        snippet: item.snippet ?? String(item.content.prefix(200)),
                        timestamp: Date(),
                        workspaceID: nil,
                        citation: citation
                    ),
                    score: item.score
                )
            }
        } catch {
            // Cancellation is expected during debounced typing - log as debug, not error
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                Log.Search.debug("Category search cancelled (superseded by newer query)")
            } else {
                lastError = error.localizedDescription
                Log.Search.error("DIndex search error: \(error.localizedDescription)")
            }
            return []
        }
    }

    // MARK: - Stats

    var stats: (count: Int, available: Bool) {
        (indexedCount, isAvailable)
    }

    private func updateStats() async {
        guard let dindex = dindexService else {
            indexedCount = 0
            return
        }

        do {
            let stats = try await dindex.getStats()
            indexedCount = stats.totalChunks
        } catch {
            Log.Search.warning("Failed to get DIndex stats: \(error.localizedDescription)")
        }
    }

    /// Refresh index statistics (call after external indexing like scraping)
    func refreshStats() async {
        await updateStats()
    }

    // MARK: - Maintenance

    /// Clear all entries from the index
    func clearIndex() async {
        guard let dindex = dindexService else {
            Log.Search.debug("clearIndex skipped: dindexService not available")
            return
        }

        do {
            try await dindex.clearAll()
            await updateStats()
            Log.Search.info("Index cleared successfully")
        } catch {
            lastError = error.localizedDescription
            Log.Search.error("Failed to clear index: \(error.localizedDescription)")
        }
    }

    /// Save/sync the index (called on app termination)
    func save() async {
        // No-op - DIndex handles persistence
    }
}

// MARK: - Bridge for existing code

extension SemanticSearchManagerV2 {
    /// For compatibility with existing SemanticSearchManager API
    @MainActor
    static var current: SemanticSearchManagerV2 {
        shared
    }
}

// MARK: - Result Types

/// Citation information from a matching chunk
struct CitationInfo {
    let content: String
    let sectionHierarchy: [String]
    let matchedBy: [String]
    let positionInDoc: Float
    let chunkScore: Float
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

    init(
        id: UInt64,
        url: String,
        title: String,
        snippet: String,
        timestamp: Date,
        workspaceID: UUID?,
        citation: CitationInfo? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.snippet = snippet
        self.timestamp = timestamp
        self.workspaceID = workspaceID
        self.citation = citation
    }
}
