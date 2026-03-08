import Foundation
import CryptoKit
import VecturaKit

/// Native on-device semantic search service powered by VecturaKit.
///
/// Coordinates text chunking, metadata tracking, and hybrid search
/// (vector + BM25) entirely on-device via VecturaKit.
actor NativeSearchService: SemanticSearchBackend {
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
        _ = try await embedder.embed(text: "semantic search health check")
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
        let searchableText = makeSearchableText(title: title, content: content)
        let domain = url.host ?? ""
        let categoryStrings = categories.map { $0.rawValue }

        // Dedup chunks if content is unchanged, but still refresh page-level metadata.
        if let existingHash = try await metadataDB.getPageHash(url: urlString),
           existingHash == contentHash {
            try await metadataDB.upsertPage(
                url: urlString,
                title: title,
                domain: domain,
                contentHash: contentHash,
                categories: categoryStrings,
                fullText: searchableText
            )
            Log.Search.debug("NativeSearchService: refreshed metadata for \(url) — content unchanged")
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

        // Upsert page first (FK parent for chunk_map)
        try await metadataDB.upsertPage(
            url: urlString,
            title: title,
            domain: domain,
            contentHash: contentHash,
            categories: categoryStrings,
            fullText: searchableText
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
        guard limit > 0 else { return [] }

        let queryTerms = tokenizeQuery(query)
        let totalChunks = try await metadataDB.getChunkCount()
        guard totalChunks > 0 else { return [] }

        let categoryFilter: Set<String>?
        if let categories, !categories.isEmpty {
            categoryFilter = Set(categories.map { $0.rawValue })
        } else {
            categoryFilter = nil
        }

        let keywordMatches = try await metadataDB.searchKeywordMatches(
            query: query,
            limit: max(limit * 3, 50)
        )
        let filteredKeywordMatches = keywordMatches.filter { match in
            guard let categoryFilter else { return true }
            return !Set(match.categories).isDisjoint(with: categoryFilter)
        }

        let maxCandidateCount = min(totalChunks, 1_000)
        var candidateCount = min(max(limit * 8, 100), maxCandidateCount)
        var assembledResults: SearchAssembly?

        while true {
            let vecturaResults = try await vectura.search(query: .text(query), numResults: candidateCount)
            guard !vecturaResults.isEmpty else { break }

            let assembly = try await assembleResults(
                from: vecturaResults,
                queryTerms: queryTerms,
                categoryFilter: categoryFilter
            )

            Log.Search.debug(
                """
                NativeSearchService.search query='\(query)' fetchedChunks=\(vecturaResults.count) \
                candidates=\(candidateCount) uniquePages=\(assembly.uniquePagesBeforeFilter) \
                filteredPages=\(assembly.uniquePagesAfterFilter) returned=\(min(limit, assembly.results.count))
                """
            )

            assembledResults = assembly

            let hasEnoughPages = assembly.uniquePagesAfterFilter >= limit
            let exhaustedResults = vecturaResults.count < candidateCount
            let exhaustedCandidates = candidateCount >= maxCandidateCount

            if hasEnoughPages || exhaustedResults || exhaustedCandidates {
                break
            }

            candidateCount = min(candidateCount * 2, maxCandidateCount)
        }

        let semanticResults = assembledResults?.results ?? []
        let mergedResults = mergeKeywordMatches(
            semanticResults: semanticResults,
            keywordMatches: filteredKeywordMatches,
            query: query,
            queryTerms: queryTerms
        )

        Log.Search.debug(
            """
            NativeSearchService.search query='\(query)' semanticPages=\(semanticResults.count) \
            keywordPages=\(filteredKeywordMatches.count) returned=\(min(limit, mergedResults.count))
            """
        )

        return Array(mergedResults.prefix(limit))
    }

    // MARK: - Stats

    func getStats() async throws -> SemanticSearchBackendStats {
        try await ensureInitialized()
        let chunks = try await metadataDB.getChunkCount()
        let docs = try await metadataDB.getPageCount()
        return SemanticSearchBackendStats(pageCount: docs, chunkCount: chunks)
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

    private struct GroupEntry {
        var best: (id: UUID, text: String, score: Float, meta: ChunkMeta)
        var additional: [(id: UUID, text: String, score: Float, meta: ChunkMeta)]
    }

    private struct SearchAssembly {
        let uniquePagesBeforeFilter: Int
        let uniquePagesAfterFilter: Int
        let results: [NativeSearchResult]
    }

    private func makeSearchableText(title: String?, content: String) -> String {
        _ = title
        return content
    }

    private func tokenizeQuery(_ query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func normalizeForMatching(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergeKeywordMatches(
        semanticResults: [NativeSearchResult],
        keywordMatches: [PageKeywordMatch],
        query: String,
        queryTerms: [String]
    ) -> [NativeSearchResult] {
        guard !keywordMatches.isEmpty else {
            return semanticResults.sorted { $0.score > $1.score }
        }

        let normalizedQuery = normalizeForMatching(query)
        var merged = Dictionary(uniqueKeysWithValues: semanticResults.map { ($0.url, $0) })

        for match in keywordMatches {
            let lexicalScore = lexicalScore(for: match, normalizedQuery: normalizedQuery, queryTerms: queryTerms)
            let keywordSnippet = bestSnippet(for: match, queryTerms: queryTerms)

            if let existing = merged[match.url] {
                merged[match.url] = NativeSearchResult(
                    url: existing.url,
                    title: existing.title ?? match.title,
                    content: existing.content,
                    score: max(existing.score, lexicalScore),
                    sectionHierarchy: existing.sectionHierarchy,
                    matchedBy: mergedMatchedBy(existing.matchedBy, ["bm25"]),
                    positionInDoc: existing.positionInDoc,
                    chunkRelevanceScore: existing.chunkRelevanceScore,
                    snippet: existing.snippet ?? keywordSnippet,
                    additionalChunks: existing.additionalChunks
                )
            } else {
                let content = match.fullText ?? match.title ?? ""
                merged[match.url] = NativeSearchResult(
                    url: match.url,
                    title: match.title,
                    content: content,
                    score: lexicalScore,
                    sectionHierarchy: [],
                    matchedBy: ["bm25"],
                    positionInDoc: 0.0,
                    chunkRelevanceScore: lexicalScore,
                    snippet: keywordSnippet,
                    additionalChunks: []
                )
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.url < rhs.url
            }
            return lhs.score > rhs.score
        }
    }

    private func bestSnippet(for match: PageKeywordMatch, queryTerms: [String]) -> String? {
        guard let fullText = match.fullText, !fullText.isEmpty else { return nil }
        return SnippetExtractor.extractSnippet(from: fullText, queryTerms: queryTerms)
    }

    private func lexicalScore(
        for match: PageKeywordMatch,
        normalizedQuery: String,
        queryTerms: [String]
    ) -> Float {
        let normalizedTitle = normalizeForMatching(match.title ?? "")
        let normalizedBody = normalizeForMatching(match.fullText ?? "")
        let matchedTerms = queryTerms.filter { term in
            normalizedTitle.contains(term) || normalizedBody.contains(term)
        }
        let coverage = queryTerms.isEmpty
            ? 0
            : Float(Set(matchedTerms).count) / Float(Set(queryTerms).count)

        let phraseInTitle = !normalizedQuery.isEmpty && normalizedTitle.contains(normalizedQuery)
        let phraseInBody = !normalizedQuery.isEmpty && normalizedBody.contains(normalizedQuery)

        var score: Float = 0.55 + (0.20 * coverage)
        if phraseInBody {
            score += 0.12
        }
        if phraseInTitle {
            score += 0.10
        } else if !matchedTerms.isEmpty && !normalizedTitle.isEmpty {
            score += 0.05
        }

        let bm25Boost = max(0.0, min(Float(-match.bm25Score) * 0.02, 0.08))
        return min(score + bm25Boost, 0.98)
    }

    private func mergedMatchedBy(_ lhs: [String], _ rhs: [String]) -> [String] {
        Array(Set(lhs).union(rhs)).sorted()
    }

    private func assembleResults(
        from vecturaResults: [VecturaSearchResult],
        queryTerms: [String],
        categoryFilter: Set<String>?
    ) async throws -> SearchAssembly {
        // Enrich with metadata
        let vecturaIds = vecturaResults.map { $0.id }
        let chunkMetas = try await metadataDB.getChunkMetadata(vecturaIds: vecturaIds)

        // Collect unique page URLs for metadata lookup
        let pageURLs = Array(Set(chunkMetas.values.map { $0.pageURL }))
        let pageMetas = try await metadataDB.getPageMetadata(urls: pageURLs)

        // Group chunks by page URL — best chunk + up to 4 additional
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
        let uniquePagesBeforeFilter = groups.count

        // Build results
        var results: [NativeSearchResult] = []
        var uniquePagesAfterFilter = 0

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
            uniquePagesAfterFilter += 1

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
        return SearchAssembly(
            uniquePagesBeforeFilter: uniquePagesBeforeFilter,
            uniquePagesAfterFilter: uniquePagesAfterFilter,
            results: results
        )
    }
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
