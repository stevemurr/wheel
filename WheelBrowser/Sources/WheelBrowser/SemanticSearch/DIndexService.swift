import Foundation
import DIndexClient

/// Wrapper around DIndexClient for indexing and searching with category support.
///
/// This actor provides a clean interface for WheelBrowser to interact with
/// a remote DIndex server for embedding-based semantic search.
actor DIndexService {
    private let client: DIndexClient

    init(endpoint: URL, apiKey: String?) {
        self.client = DIndexClient(baseURL: endpoint, apiKey: apiKey)
    }

    /// Index a page with category tags
    ///
    /// - Parameters:
    ///   - url: The page URL
    ///   - title: Optional page title
    ///   - content: The page content to index
    ///   - categories: Set of categories to tag this content with
    func indexPage(
        url: URL,
        title: String?,
        content: String,
        categories: Set<EmbeddingCategory>
    ) async throws {
        let categoryStrings = categories.map { $0.rawValue }
        Log.Search.debug("DIndexService.indexPage: url=\(url.absoluteString), title=\(title ?? "nil"), contentLength=\(content.count), categories=\(categoryStrings)")
        let response = try await client.index(
            content: content,
            title: title,
            url: url.absoluteString,
            categories: categoryStrings
        )
        Log.Search.debug("DIndexService.indexPage completed: chunks=\(response.chunksCreated)")
    }

    /// Search with optional category filtering
    ///
    /// - Parameters:
    ///   - query: The search query text
    ///   - categories: Optional set of categories to filter by (nil = no filter)
    ///   - limit: Maximum number of results to return
    /// - Returns: Array of search results
    func search(
        query: String,
        categories: Set<EmbeddingCategory>? = nil,
        limit: Int = 20
    ) async throws -> [DIndexSearchItem] {
        Log.Search.debug("DIndexService.search: query='\(query)', categories=\(categories?.map { $0.rawValue } ?? []), limit=\(limit)")
        let results: [DIndexSearchItem]
        if let cats = categories, !cats.isEmpty {
            let categoryStrings = cats.map { $0.rawValue }
            let response = try await client.search(query: query, categories: categoryStrings, topK: limit)
            results = response.results.map { DIndexSearchItem(chunk: $0.chunk, score: $0.relevanceScore) }
        } else {
            let response = try await client.search(query: query, topK: limit)
            results = response.results.map { DIndexSearchItem(chunk: $0.chunk, score: $0.relevanceScore) }
        }
        Log.Search.debug("DIndexService.search returned \(results.count) results")
        return results
    }

    /// Check if the DIndex server is healthy and reachable
    func checkHealth() async -> Bool {
        Log.Search.debug("DIndexService.checkHealth starting...")
        do {
            let healthy = try await client.health()
            Log.Search.debug("DIndexService.checkHealth result: \(healthy)")
            return healthy
        } catch {
            Log.Search.warning("DIndex health check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Get index statistics from the server
    func getStats() async throws -> IndexStats {
        Log.Search.debug("DIndexService.getStats fetching...")
        let stats = try await client.stats()
        Log.Search.debug("DIndexService.getStats: totalChunks=\(stats.totalChunks), totalDocuments=\(stats.totalDocuments)")
        return stats
    }
}

/// A search result from DIndex, converted to a local-friendly format
struct DIndexSearchItem: Identifiable, Sendable {
    let id: String
    let url: String?
    let title: String?
    let content: String
    let score: Float

    init(chunk: Chunk, score: Float) {
        self.id = chunk.metadata.chunkId
        self.url = chunk.metadata.sourceUrl
        self.title = chunk.metadata.sourceTitle
        self.content = chunk.content
        self.score = score
    }
}
