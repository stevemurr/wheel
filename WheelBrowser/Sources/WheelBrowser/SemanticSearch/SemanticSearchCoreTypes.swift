import Foundation

struct SemanticSearchStats: Sendable, Equatable {
    var pageCount: Int
    var chunkCount: Int
    var pendingCount: Int
    var available: Bool

    static let empty = SemanticSearchStats(
        pageCount: 0,
        chunkCount: 0,
        pendingCount: 0,
        available: false
    )
}

struct SemanticSearchBackendStats: Sendable, Equatable {
    let pageCount: Int
    let chunkCount: Int
}

protocol SemanticSearchBackend: Sendable {
    func validateBackend() async throws
    func indexPage(
        url: URL,
        title: String?,
        content: String,
        categories: Set<EmbeddingCategory>
    ) async throws
    func search(
        query: String,
        categories: Set<EmbeddingCategory>?,
        limit: Int
    ) async throws -> [NativeSearchResult]
    func getStats() async throws -> SemanticSearchBackendStats
    func clearAll() async throws
}
