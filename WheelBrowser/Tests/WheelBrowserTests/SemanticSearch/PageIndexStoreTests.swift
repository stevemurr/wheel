import Foundation
import SQLite3
import Testing
@testable import WheelBrowser

@Suite("PageIndexStore")
struct PageIndexStoreTests {
    @Test("Migrates reading-list and semantic metadata into unified store")
    func migratesLegacyStoresIntoUnifiedIndex() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let readingListPath = tempDir.appendingPathComponent("semantic_search.db")
        let metadataPath = tempDir.appendingPathComponent("semantic_search_meta.db")
        let unifiedPath = tempDir.appendingPathComponent("page_index.db")
        let vecturaID = UUID()

        try createLegacyReadingList(at: readingListPath)
        try createLegacyMetadata(at: metadataPath, vecturaID: vecturaID)

        let store = try PageIndexStore(
            dbPath: unifiedPath,
            legacyReadingListPath: readingListPath,
            legacyMetadataPath: metadataPath
        )
        try await store.initialize()

        let savedPages = try await store.getSavedPages(limit: 10)
        #expect(savedPages.count == 1)
        #expect(savedPages.first?.title == "Saved Page")
        #expect(savedPages.first?.summary == "Reading list summary")

        let pageHash = try await store.getPageHash(url: "https://example.com/saved")
        #expect(pageHash == "hash-123")

        let chunkMetadata = try await store.getChunkMetadata(vecturaIds: [vecturaID])
        #expect(chunkMetadata[vecturaID]?.pageURL == "https://example.com/saved")
        #expect(chunkMetadata[vecturaID]?.sectionHierarchy == ["Intro"])

        let pageMetadata = try await store.getPageMetadata(urls: ["https://example.com/saved"])
        #expect(pageMetadata["https://example.com/saved"]?.categories == ["docs"])

        let keywordMatches = try await store.searchKeywordMatches(query: "swift guide", limit: 5)
        #expect(keywordMatches.count == 1)
        #expect(keywordMatches.first?.url == "https://example.com/saved")
    }

    @Test("Clearing semantic index preserves saved pages")
    func clearAllPreservesReadingListRecords() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let store = try PageIndexStore(dbPath: tempDir.appendingPathComponent("page_index.db"))
        try await store.initialize()

        _ = try await store.upsertPage(
            url: URL(string: "https://example.com/saved")!,
            title: "Saved Page"
        )
        try await store.setSaved(url: "https://example.com/saved", saved: true)
        try await store.updateSummary(url: "https://example.com/saved", summary: "Keep me")
        try await store.upsertPage(
            url: "https://example.com/saved",
            title: "Saved Page",
            domain: "example.com",
            contentHash: "hash-123",
            categories: ["docs"],
            fullText: "Swift guide body"
        )
        let vecturaID = UUID()
        try await store.addChunkMapping(
            vecturaId: vecturaID,
            pageURL: "https://example.com/saved",
            sectionHierarchy: ["Intro"],
            positionInDoc: 0.1
        )

        try await store.clearAll()

        let savedPages = try await store.getSavedPages(limit: 10)
        #expect(savedPages.count == 1)
        #expect(savedPages.first?.summary == "Keep me")
        #expect(try await store.getPageHash(url: "https://example.com/saved") == nil)
        #expect(try await store.getChunkCount() == 0)
        #expect(try await store.getPageCount() == 0)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func createLegacyReadingList(at path: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path.path, &db) == SQLITE_OK else {
            throw SearchDBError.failedToOpen("legacy reading list")
        }
        defer { sqlite3_close(db) }

        try exec(
            """
            CREATE TABLE pages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT NOT NULL UNIQUE,
                title TEXT,
                domain TEXT,
                full_text TEXT,
                summary TEXT,
                first_visited_at INTEGER NOT NULL DEFAULT 0,
                last_visited_at INTEGER NOT NULL DEFAULT 0,
                visit_count INTEGER DEFAULT 1,
                workspace_id TEXT,
                is_saved INTEGER DEFAULT 0,
                saved_at INTEGER
            );
            """,
            on: db
        )
        try exec(
            """
            INSERT INTO pages (
                url, title, domain, summary, first_visited_at, last_visited_at, visit_count, is_saved, saved_at
            ) VALUES (
                'https://example.com/saved',
                'Saved Page',
                'example.com',
                'Reading list summary',
                100,
                200,
                3,
                1,
                300
            );
            """,
            on: db
        )
    }

    private func createLegacyMetadata(at path: URL, vecturaID: UUID) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path.path, &db) == SQLITE_OK else {
            throw SearchDBError.failedToOpen("legacy metadata")
        }
        defer { sqlite3_close(db) }

        try exec(
            """
            CREATE TABLE indexed_pages (
                url TEXT PRIMARY KEY,
                title TEXT,
                domain TEXT,
                content_hash TEXT NOT NULL,
                categories TEXT,
                full_text TEXT,
                indexed_at INTEGER NOT NULL
            );
            """,
            on: db
        )
        try exec(
            """
            CREATE TABLE chunk_map (
                vectura_id TEXT PRIMARY KEY,
                page_url TEXT NOT NULL,
                section_hierarchy TEXT,
                position_in_doc REAL
            );
            """,
            on: db
        )
        try exec(
            """
            INSERT INTO indexed_pages (
                url, title, domain, content_hash, categories, full_text, indexed_at
            ) VALUES (
                'https://example.com/saved',
                'Saved Page',
                'example.com',
                'hash-123',
                '["docs"]',
                'Swift guide body for migration tests',
                400
            );
            """,
            on: db
        )
        try exec(
            """
            INSERT INTO chunk_map (
                vectura_id, page_url, section_hierarchy, position_in_doc
            ) VALUES (
                '\(vecturaID.uuidString)',
                'https://example.com/saved',
                '["Intro"]',
                0.25
            );
            """,
            on: db
        )
    }

    private func exec(_ sql: String, on db: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw SearchDBError.executeFailed(message)
        }
    }
}
