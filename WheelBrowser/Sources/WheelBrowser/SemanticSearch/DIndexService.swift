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
        let response: SearchResponse
        if let cats = categories, !cats.isEmpty {
            let categoryStrings = cats.map { $0.rawValue }
            response = try await client.search(query: query, categories: categoryStrings, topK: limit)
        } else {
            response = try await client.search(query: query, topK: limit)
        }
        // Return one result per document using the best chunk's content
        let results = response.results.compactMap { group -> DIndexSearchItem? in
            guard let bestChunk = group.chunks.first else { return nil }
            return DIndexSearchItem(
                id: group.documentId,
                url: group.sourceUrl,
                title: group.sourceTitle,
                content: bestChunk.content,
                score: group.relevanceScore,
                sectionHierarchy: bestChunk.sectionHierarchy,
                matchedBy: bestChunk.matchedBy,
                positionInDoc: bestChunk.positionInDoc,
                chunkRelevanceScore: bestChunk.relevanceScore
            )
        }
        Log.Search.debug("DIndexService.search returned \(results.count) results (\(response.totalDocuments) documents)")
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

    /// Clear all entries from the index
    func clearAll() async throws {
        Log.Search.debug("DIndexService.clearAll starting...")
        let response = try await client.clearAll()
        Log.Search.info("DIndexService.clearAll completed: chunksDeleted=\(response.chunksDeleted)")
    }
}

/// A search result from DIndex, converted to a local-friendly format
struct DIndexSearchItem: Identifiable, Sendable {
    let id: String
    let url: String?
    let title: String?
    let content: String
    let score: Float
    // Chunk metadata for citation display
    let sectionHierarchy: [String]
    let matchedBy: [String]
    let positionInDoc: Float
    let chunkRelevanceScore: Float

    init(
        id: String,
        url: String?,
        title: String?,
        content: String,
        score: Float,
        sectionHierarchy: [String] = [],
        matchedBy: [String] = [],
        positionInDoc: Float = 0.0,
        chunkRelevanceScore: Float = 0.0
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.content = content
        self.score = score
        self.sectionHierarchy = sectionHierarchy
        self.matchedBy = matchedBy
        self.positionInDoc = positionInDoc
        self.chunkRelevanceScore = chunkRelevanceScore
    }
}

// MARK: - Scraping Support

extension DIndexService {
    /// Start a web scraping job
    ///
    /// - Parameters:
    ///   - url: The URL to start scraping from
    ///   - depth: Maximum crawl depth (0 = current page only)
    ///   - stayOnDomain: Whether to stay on the same domain
    ///   - maxPages: Maximum number of pages to scrape
    /// - Returns: The job ID for tracking progress
    func startScrape(
        url: URL,
        depth: UInt8 = 2,
        stayOnDomain: Bool = true,
        maxPages: Int = 100
    ) async throws -> String {
        Log.Search.debug("DIndexService.startScrape: url=\(url.absoluteString), depth=\(depth), stayOnDomain=\(stayOnDomain), maxPages=\(maxPages)")
        let options = ScrapeOptions(
            maxDepth: depth,
            stayOnDomain: stayOnDomain,
            delayMs: 1000,
            maxPages: maxPages
        )
        let response = try await client.startScrape(url: url.absoluteString, options: options)
        Log.Search.debug("DIndexService.startScrape completed: jobId=\(response.jobId)")
        return response.jobId
    }

    /// Get the progress of a scraping job
    ///
    /// - Parameter jobId: The job ID returned from startScrape
    /// - Returns: Current job progress
    func getScrapeProgress(jobId: String) async throws -> JobProgress {
        Log.Search.debug("DIndexService.getScrapeProgress: jobId=\(jobId)")
        let progress = try await client.getJobProgress(jobId: jobId)
        Log.Search.debug("DIndexService.getScrapeProgress: stage=\(progress.stage), current=\(progress.current), total=\(progress.total ?? 0)")
        return progress
    }

    /// Cancel a running scrape job
    ///
    /// - Parameter jobId: The job ID to cancel
    func cancelScrape(jobId: String) async throws {
        Log.Search.debug("DIndexService.cancelScrape: jobId=\(jobId)")
        _ = try await client.cancelJob(jobId: jobId)
        Log.Search.info("DIndexService.cancelScrape completed")
    }

    /// Subscribe to real-time events for a scrape job via SSE
    ///
    /// - Parameter jobId: The job ID to subscribe to
    /// - Returns: An async stream of scrape events
    nonisolated func subscribeScrapeEvents(jobId: String) -> AsyncThrowingStream<ScrapeEvent, Error> {
        Log.Search.debug("DIndexService.subscribeScrapeEvents: jobId=\(jobId)")
        return client.subscribeToJobEvents(jobId: jobId)
    }
}
