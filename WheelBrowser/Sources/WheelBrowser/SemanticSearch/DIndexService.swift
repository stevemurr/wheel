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
        _ = try await client.index(
            content: content,
            title: title,
            url: url.absoluteString,
            categories: categoryStrings
        )
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
        if let cats = categories, !cats.isEmpty {
            let categoryStrings = cats.map { $0.rawValue }
            let response = try await client.search(query: query, categories: categoryStrings, topK: limit)
            return response.results.map { DIndexSearchItem(chunk: $0.chunk, score: $0.relevanceScore) }
        } else {
            let response = try await client.search(query: query, topK: limit)
            return response.results.map { DIndexSearchItem(chunk: $0.chunk, score: $0.relevanceScore) }
        }
    }

    /// Check if the DIndex server is healthy and reachable
    func checkHealth() async -> Bool {
        do {
            return try await client.health()
        } catch {
            return false
        }
    }

    /// Get index statistics from the server
    func getStats() async throws -> IndexStats {
        try await client.stats()
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
