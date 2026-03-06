import Foundation
import CryptoKit
import VecturaKit

/// Native on-device semantic search service powered by VecturaKit.
///
/// Coordinates text chunking, metadata tracking, and hybrid search
/// (vector + BM25) entirely on-device via VecturaKit.
actor NativeSearchService {
    private var vecturaDB: VecturaKit?
    private let metadataDB: ChunkMetadataDB
    private let embedder: any VecturaEmbedder
    private let storageURL: URL
    private var isInitialized = false

    init(dbPath: URL? = nil) {
        let baseDir = dbPath?.deletingLastPathComponent()
            ?? FileManager.appSupportDirectory
        self.storageURL = baseDir.appendingPathComponent("vectura-search")
        self.metadataDB = ChunkMetadataDB(dbPath: dbPath)
        self.embedder = SwiftEmbedder()
    }

    /// For tests: inject a mock embedder
    init(dbPath: URL? = nil, embedder: any VecturaEmbedder) {
        let baseDir = dbPath?.deletingLastPathComponent()
            ?? FileManager.appSupportDirectory
        self.storageURL = baseDir.appendingPathComponent("vectura-search")
        self.metadataDB = ChunkMetadataDB(dbPath: dbPath)
        self.embedder = embedder
    }

    private func ensureInitialized() async throws {
        guard !isInitialized else { return }
        let config = try VecturaConfig(
            name: "wheel-search",
            directoryURL: storageURL,
            searchOptions: .init(
                defaultNumResults: 100,
                hybridWeight: 0.5
            )
        )
        self.vecturaDB = try await VecturaKit(config: config, embedder: embedder)
        try await metadataDB.ensureInitialized()
        isInitialized = true
    }

    /// Force early embedder/model initialization so callers can fail fast
    /// and disable semantic search instead of retrying on every operation.
    func validateBackend() async throws {
        try await ensureInitialized()
        _ = try await embedder.dimension
    }

    // MARK: - Indexing

    /// Index a page: chunk → embed → store via VecturaKit + metadata mapping
    func indexPage(
        url: URL,
        title: String?,
        content: String,
        categories: Set<EmbeddingCategory>
    ) async throws {
        try await ensureInitialized()
        guard let vectura = vecturaDB else { return }

        let urlString = url.absoluteString
        let contentHash = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        // Dedup: skip if content unchanged
        if let existingHash = try await metadataDB.getPageHash(url: urlString),
           existingHash == contentHash {
            Log.Search.debug("NativeSearchService: skipping \(url) — content unchanged")
            return
        }

        // Content changed or new — delete old chunks from VecturaKit + metadata
        let oldIds = try await metadataDB.deleteChunksForPage(url: urlString)
        if !oldIds.isEmpty {
            try await vectura.deleteDocuments(ids: oldIds)
        }

        // Chunk the text
        let chunks = TextChunker.chunk(text: content)
        guard !chunks.isEmpty else {
            Log.Search.debug("NativeSearchService: no chunks produced for \(url)")
            return
        }

        let domain = url.host ?? ""
        let categoryStrings = categories.map { $0.rawValue }

        // Upsert page first (FK parent for chunk_map)
        try await metadataDB.upsertPage(
            url: urlString,
            title: title,
            domain: domain,
            contentHash: contentHash,
            categories: categoryStrings
        )

        // Add chunks to VecturaKit and track the mapping
        let chunkTexts = chunks.map { $0.content }
        let chunkIds = try await vectura.addDocuments(texts: chunkTexts)

        for (i, chunkId) in chunkIds.enumerated() {
            try await metadataDB.addChunkMapping(
                vecturaId: chunkId,
                pageURL: urlString,
                sectionHierarchy: chunks[i].sectionHierarchy,
                positionInDoc: chunks[i].positionInDoc
            )
        }

        Log.Search.info("NativeSearchService: indexed \(url) — \(chunks.count) chunks")
    }

    // MARK: - Search

    /// Hybrid search: vector + BM25 via VecturaKit, enriched with page metadata
    func search(
        query: String,
        categories: Set<EmbeddingCategory>? = nil,
        limit: Int = 20
    ) async throws -> [NativeSearchResult] {
        try await ensureInitialized()
        guard let vectura = vecturaDB else { return [] }

        let queryTerms = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        // VecturaKit handles hybrid search (vector + BM25)
        let vecturaResults = try await vectura.search(query: .text(query), numResults: 100)
        guard !vecturaResults.isEmpty else { return [] }

        // Enrich with metadata
        let vecturaIds = vecturaResults.map { $0.id }
        let chunkMetas = try await metadataDB.getChunkMetadata(vecturaIds: vecturaIds)

        // Collect unique page URLs for metadata lookup
        let pageURLs = Array(Set(chunkMetas.values.map { $0.pageURL }))
        let pageMetas = try await metadataDB.getPageMetadata(urls: pageURLs)

        // Group chunks by page URL — best chunk + up to 4 additional
        struct GroupEntry {
            var best: (id: UUID, text: String, score: Float, meta: ChunkMeta)
            var additional: [(id: UUID, text: String, score: Float, meta: ChunkMeta)]
        }
        var groups: [String: GroupEntry] = [:]

        for result in vecturaResults {
            guard let meta = chunkMetas[result.id] else { continue }
            let entry = (id: result.id, text: result.text, score: result.score, meta: meta)

            if groups[meta.pageURL] == nil {
                groups[meta.pageURL] = GroupEntry(best: entry, additional: [])
            } else if groups[meta.pageURL]!.additional.count < 4 {
                groups[meta.pageURL]!.additional.append(entry)
            }
        }

        // Apply category filter if specified
        let categoryFilter: Set<String>?
        if let categories, !categories.isEmpty {
            categoryFilter = Set(categories.map { $0.rawValue })
        } else {
            categoryFilter = nil
        }

        // Build results
        var results: [NativeSearchResult] = []

        for (pageURL, group) in groups {
            // Category filter
            if let filter = categoryFilter {
                guard let pageMeta = pageMetas[pageURL] else { continue }
                let docCategories = Set(pageMeta.categories)
                guard !docCategories.isDisjoint(with: filter) else { continue }
            }

            let pageMeta = pageMetas[pageURL]
            let snippet = SnippetExtractor.extractSnippet(
                from: group.best.text,
                queryTerms: queryTerms
            )

            let additionalChunks = group.additional.map { item in
                NativeChunkInfo(
                    content: item.text,
                    snippet: SnippetExtractor.extractSnippet(from: item.text, queryTerms: queryTerms),
                    sectionHierarchy: item.meta.sectionHierarchy,
                    matchedBy: ["hybrid"],
                    positionInDoc: item.meta.positionInDoc,
                    relevanceScore: item.score
                )
            }

            results.append(NativeSearchResult(
                url: pageURL,
                title: pageMeta?.title,
                content: group.best.text,
                score: group.best.score,
                sectionHierarchy: group.best.meta.sectionHierarchy,
                matchedBy: ["hybrid"],
                positionInDoc: group.best.meta.positionInDoc,
                chunkRelevanceScore: group.best.score,
                snippet: snippet,
                additionalChunks: additionalChunks
            ))
        }

        // Sort by score descending, limit
        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    // MARK: - Stats

    func getStats() async throws -> (totalChunks: Int, totalDocuments: Int) {
        try await ensureInitialized()
        let chunks = try await metadataDB.getChunkCount()
        let docs = try await metadataDB.getPageCount()
        return (chunks, docs)
    }

    // MARK: - Maintenance

    func clearAll() async throws {
        try await ensureInitialized()
        guard let vectura = vecturaDB else { return }
        try await vectura.reset()
        try await metadataDB.clearAll()
    }

    /// Always healthy — we're local
    func checkHealth() -> Bool { true }
}

// MARK: - Result Types

/// A native search result
struct NativeSearchResult: Sendable {
    let url: String
    let title: String?
    let content: String
    let score: Float
    let sectionHierarchy: [String]
    let matchedBy: [String]
    let positionInDoc: Float
    let chunkRelevanceScore: Float
    let snippet: String?
    let additionalChunks: [NativeChunkInfo]
}

/// Additional chunk info for citation display
struct NativeChunkInfo: Sendable {
    let content: String
    let snippet: String?
    let sectionHierarchy: [String]
    let matchedBy: [String]
    let positionInDoc: Float
    let relevanceScore: Float
}
