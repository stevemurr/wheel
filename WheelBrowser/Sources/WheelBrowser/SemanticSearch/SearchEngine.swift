import Foundation

/// Hybrid search engine combining vector and full-text search
actor SearchEngine {
    private let db: SearchDatabase
    private let embeddingService: any EmbeddingService

    private let topK = 50                    // candidates per method
    private let finalK = 20                  // final results
    private let timeDecayDays: Double = 30   // half-life for time decay

    init(db: SearchDatabase, embeddingService: any EmbeddingService) {
        self.db = db
        self.embeddingService = embeddingService
    }

    /// Perform hybrid search combining vector and FTS
    func search(query: String, workspaceID: UUID? = nil) async throws -> [SearchResult] {
        // Generate query embedding
        let queryEmbedding = try await embeddingService.embed(text: query)

        // Parallel retrieval
        async let vectorTask = hierarchicalVectorSearch(embedding: queryEmbedding)
        async let ftsTask = fullTextSearch(query: query)

        let (vectorResults, ftsResults) = try await (vectorTask, ftsTask)

        // Reciprocal Rank Fusion
        let fused = reciprocalRankFusion(rankings: [vectorResults, ftsResults], k: 60)

        // Apply time decay and frequency boost
        let scored = try await applyTimeDecay(results: fused)

        // Filter by workspace if specified
        let filtered: [(Int64, Double)]
        if let workspaceID = workspaceID {
            filtered = try await filterByWorkspace(results: scored, workspaceID: workspaceID)
        } else {
            filtered = scored
        }

        // Build final results
        return try await buildResults(from: Array(filtered.prefix(finalK)))
    }

    /// Search using only FTS (for quick keyword matches)
    func quickSearch(query: String, limit: Int = 10) async throws -> [SearchResult] {
        let ftsResults = try await db.ftsSearch(table: "pages_fts", query: query, limit: limit)
        return try await buildResults(from: ftsResults)
    }

    // MARK: - Private

    private func hierarchicalVectorSearch(embedding: [Float]) async throws -> [(Int64, Double)] {
        // Level 1: Search summary embeddings (document level)
        let summaryMatches = try await db.vectorSearch(
            table: "pages_summary_vec",
            embedding: embedding,
            limit: topK
        )

        // Level 2: Search title embeddings
        let titleMatches = try await db.vectorSearch(
            table: "pages_title_vec",
            embedding: embedding,
            limit: topK / 2
        )

        // Level 3: Search chunk embeddings within top documents
        let topPageIds = summaryMatches.prefix(20).map { $0.0 }
        let chunkMatches = try await db.vectorSearchChunks(
            embedding: embedding,
            pageIds: Array(topPageIds),
            limit: topK
        )

        // Combine with weights
        var scores: [Int64: Double] = [:]

        for (id, score) in summaryMatches {
            scores[id, default: 0] += score * 0.4
        }
        for (id, score) in titleMatches {
            scores[id, default: 0] += score * 0.2
        }
        for (id, score) in chunkMatches {
            scores[id, default: 0] += score * 0.4
        }

        return scores.sorted { $0.value > $1.value }
    }

    private func fullTextSearch(query: String) async throws -> [(Int64, Double)] {
        // FTS on pages (title, summary)
        let pageMatches = try await db.ftsSearch(table: "pages_fts", query: query, limit: topK)

        // FTS on chunks
        let chunkMatches = try await db.ftsSearchChunks(query: query, limit: topK)

        // Combine
        var scores: [Int64: Double] = [:]
        for (id, score) in pageMatches {
            scores[id, default: 0] += score * 0.4
        }
        for (id, score) in chunkMatches {
            scores[id, default: 0] += score * 0.6
        }

        return scores.sorted { $0.value > $1.value }
    }

    private func reciprocalRankFusion(
        rankings: [[(Int64, Double)]],
        k: Double
    ) -> [(Int64, Double)] {
        var scores: [Int64: Double] = [:]

        for ranking in rankings {
            for (rank, (id, _)) in ranking.enumerated() {
                scores[id, default: 0] += 1.0 / (k + Double(rank + 1))
            }
        }

        return scores.sorted { $0.value > $1.value }
    }

    private func applyTimeDecay(results: [(Int64, Double)]) async throws -> [(Int64, Double)] {
        let now = Date()

        return try await withThrowingTaskGroup(of: (Int64, Double)?.self) { group in
            for (id, score) in results {
                group.addTask {
                    guard let page = try await self.db.getPage(id: id) else { return nil }

                    let daysSinceVisit = now.timeIntervalSince(page.lastVisitedAt) / 86400
                    let decay = pow(0.5, daysSinceVisit / self.timeDecayDays)

                    // Boost by visit frequency (log scale)
                    let frequencyBoost = 1.0 + log(Double(page.visitCount + 1)) * 0.1

                    return (id, score * decay * frequencyBoost)
                }
            }

            var scored: [(Int64, Double)] = []
            for try await result in group {
                if let r = result {
                    scored.append(r)
                }
            }

            return scored.sorted { $0.1 > $1.1 }
        }
    }

    private func filterByWorkspace(results: [(Int64, Double)], workspaceID: UUID) async throws -> [(Int64, Double)] {
        var filtered: [(Int64, Double)] = []

        for (id, score) in results {
            if let page = try await db.getPage(id: id), page.workspaceID == workspaceID {
                filtered.append((id, score))
            }
        }

        return filtered
    }

    private func buildResults(from results: [(Int64, Double)]) async throws -> [SearchResult] {
        var searchResults: [SearchResult] = []

        for (pageId, score) in results {
            guard let page = try await db.getPage(id: pageId) else { continue }
            let chunks = try await db.getChunks(pageId: pageId)

            searchResults.append(SearchResult(
                id: UInt64(pageId),
                page: page,
                matchedChunks: chunks,
                score: Float(score)
            ))
        }

        return searchResults
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id: UInt64
    let page: PageRecord
    let matchedChunks: [ChunkRecord]
    let score: Float

    var snippet: String {
        matchedChunks.first?.text ?? page.snippet
    }
}
