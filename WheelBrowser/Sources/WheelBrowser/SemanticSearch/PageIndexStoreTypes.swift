import Foundation
import SQLite3

struct SavedPageRecord: Identifiable, Sendable {
    let id: Int64
    let url: URL
    let title: String?
    let domain: String
    let summary: String?
    let savedAt: Date
    let lastVisitedAt: Date

    var displayTitle: String {
        title ?? domain
    }

    var snippet: String {
        summary ?? ""
    }
}

struct ChunkMeta: Sendable {
    let pageURL: String
    let sectionHierarchy: [String]
    let positionInDoc: Float
}

struct PageMeta: Sendable {
    let url: String
    let title: String?
    let domain: String
    let categories: [String]
}

struct PageKeywordMatch: Sendable {
    let url: String
    let title: String?
    let fullText: String?
    let categories: [String]
    let bm25Score: Double
}

enum SearchDBError: Error, LocalizedError {
    case failedToOpen(String)
    case prepareFailed(String)
    case executeFailed(String)

    var errorDescription: String? {
        switch self {
        case .failedToOpen(let msg): return "Failed to open database: \(msg)"
        case .prepareFailed(let msg): return "SQL prepare failed: \(msg)"
        case .executeFailed(let msg): return "SQL execution failed: \(msg)"
        }
    }
}

protocol SummaryRepository: Actor {
    func initialize() throws
    func updateSummary(url: String, summary: String) throws
    func clearAllSummaries() throws
    func getSavedPages(limit: Int) throws -> [SavedPageRecord]
    func getSavedPagesWithoutSummary(limit: Int) throws -> [SavedPageRecord]
}

protocol SemanticPageIndexingStore: Actor {
    func initialize() throws
    func getPageHash(url: String) throws -> String?
    func upsertPage(
        url: String,
        title: String?,
        domain: String,
        contentHash: String,
        categories: [String],
        fullText: String?
    ) throws
    func addChunkMapping(vecturaId: UUID, pageURL: String, sectionHierarchy: [String], positionInDoc: Float) throws
    func getChunkMetadata(vecturaIds: [UUID]) throws -> [UUID: ChunkMeta]
    func getPageMetadata(urls: [String]) throws -> [String: PageMeta]
    func searchKeywordMatches(query: String, limit: Int) throws -> [PageKeywordMatch]
    func deleteChunksForPage(url: String) throws -> [UUID]
    func getChunkCount() throws -> Int
    func getPageCount() throws -> Int
    func clearAll() throws
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
