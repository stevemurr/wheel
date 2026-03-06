import Foundation
import SwiftUI

/// Manages semantic search using native on-device embeddings and hybrid search
@MainActor
@Observable
class SemanticSearchManagerV2 {
    static let shared = SemanticSearchManagerV2()

    private(set) var isIndexing = false
    private(set) var indexedCount: Int = 0
    private(set) var pendingCount: Int = 0
    private(set) var lastError: String?
    private(set) var isAvailable = false

    @ObservationIgnored private var searchService: NativeSearchService?

    private var settings: AppSettings { AppSettings.shared }

    private init() {
        Task {
            await initialize()
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        Log.Search.debug("SemanticSearchManagerV2 initializing (native mode)")

        guard settings.semanticSearchEnabled else {
            Log.Search.info("Semantic search disabled in settings")
            isAvailable = false
            return
        }

        searchService = NativeSearchService()
        isAvailable = true
        lastError = nil
        Log.Search.info("Native search service initialized")
        await updateStats()
    }

    /// Reinitialize with new settings
    func reinitialize() async {
        searchService = nil
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
        Log.Search.debug("indexPage called: url=\(url), title=\(title), contentLength=\(content.count)")

        guard isAvailable, let service = searchService else {
            Log.Search.debug("indexPage skipped: isAvailable=\(isAvailable)")
            return
        }
        guard let pageURL = URL(string: url) else {
            Log.Search.debug("indexPage skipped: invalid URL '\(url)'")
            return
        }

        isIndexing = true
        defer { isIndexing = false }

        do {
            try await service.indexPage(
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
            let results = try await service.search(query: query, limit: limit)
            Log.Search.debug("search completed: \(results.count) results for '\(query)'")
            return results.map { makeResult(from: $0) }
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
            let results = try await service.search(
                query: query,
                categories: categories.isEmpty ? nil : categories,
                limit: limit
            )
            Log.Search.debug("searchWithCategories completed: \(results.count) results for '\(query)'")
            return results.map { makeResult(from: $0) }
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

    var stats: (count: Int, available: Bool) {
        (indexedCount, isAvailable)
    }

    private func updateStats() async {
        guard let service = searchService else {
            indexedCount = 0
            return
        }

        do {
            let stats = try await service.getStats()
            indexedCount = stats.totalChunks
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
            try await service.clearAll()
            await updateStats()
            Log.Search.info("Index cleared successfully")
        } catch {
            lastError = error.localizedDescription
            Log.Search.error("Failed to clear index: \(error.localizedDescription)")
        }
    }

    /// Save/sync the index (called on app termination)
    func save() async {
        // No-op — SQLite handles persistence via WAL
    }
}

// MARK: - Bridge for existing code

extension SemanticSearchManagerV2 {
    @MainActor
    static var current: SemanticSearchManagerV2 {
        shared
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
