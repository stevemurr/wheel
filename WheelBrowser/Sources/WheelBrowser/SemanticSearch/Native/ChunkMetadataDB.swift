import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Metadata about a chunk mapping (VecturaKit UUID → page context)
struct ChunkMeta: Sendable {
    let pageURL: String
    let sectionHierarchy: [String]
    let positionInDoc: Float
}

/// Metadata about an indexed page
struct PageMeta: Sendable {
    let url: String
    let title: String?
    let domain: String
    let categories: [String]
}

/// Exact-match candidate returned from the page-level keyword index.
struct PageKeywordMatch: Sendable {
    let url: String
    let title: String?
    let fullText: String?
    let categories: [String]
    let bm25Score: Double
}

/// Lightweight SQLite store mapping VecturaKit document UUIDs back to page metadata.
/// VecturaKit stores the text + embeddings; this DB tracks which page each chunk came from.
actor ChunkMetadataDB {
    private static let ftsSanitizeRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "[\"'\\-\\+\\*\\(\\)\\{\\}\\[\\]\\^\\~\\:\\@\\#\\$\\%\\&]",
            options: []
        ) else {
            fatalError("ChunkMetadataDB: FTS sanitize regex is invalid")
        }
        return regex
    }()

    private var db: OpaquePointer?
    private let dbPath: URL
    private var isInitialized = false

    init(dbPath: URL? = nil) {
        self.dbPath = dbPath ?? FileManager.appSupportDirectory.appendingPathComponent("semantic_search_meta.db")
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func ensureInitialized() throws {
        guard !isInitialized else { return }
        try openDatabase()
        try createSchema()
        isInitialized = true
    }

    // MARK: - Page Operations

    func getPageHash(url: String) throws -> String? {
        try ensureInitialized()
        let sql = "SELECT content_hash FROM indexed_pages WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let ptr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: ptr)
    }

    func upsertPage(
        url: String,
        title: String?,
        domain: String,
        contentHash: String,
        categories: [String],
        fullText: String?
    ) throws {
        try ensureInitialized()
        let now = Int64(Date().timeIntervalSince1970)
        let categoriesJSON = (try? JSONSerialization.data(withJSONObject: categories))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let sql = """
            INSERT INTO indexed_pages (url, title, domain, content_hash, categories, full_text, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = COALESCE(excluded.title, title),
                domain = excluded.domain,
                content_hash = excluded.content_hash,
                categories = excluded.categories,
                full_text = excluded.full_text,
                indexed_at = excluded.indexed_at
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)
        if let title { sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 2) }
        sqlite3_bind_text(stmt, 3, domain, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, categoriesJSON, -1, SQLITE_TRANSIENT)
        if let fullText { sqlite3_bind_text(stmt, 6, fullText, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 6) }
        sqlite3_bind_int64(stmt, 7, now)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Chunk Mapping Operations

    func addChunkMapping(vecturaId: UUID, pageURL: String, sectionHierarchy: [String], positionInDoc: Float) throws {
        try ensureInitialized()
        let hierarchyJSON = (try? JSONSerialization.data(withJSONObject: sectionHierarchy))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let sql = """
            INSERT OR REPLACE INTO chunk_map (vectura_id, page_url, section_hierarchy, position_in_doc)
            VALUES (?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, vecturaId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, pageURL, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, hierarchyJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, Double(positionInDoc))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func getChunkMetadata(vecturaIds: [UUID]) throws -> [UUID: ChunkMeta] {
        try ensureInitialized()
        guard !vecturaIds.isEmpty else { return [:] }

        let placeholders = vecturaIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT vectura_id, page_url, section_hierarchy, position_in_doc
            FROM chunk_map WHERE vectura_id IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        for (i, id) in vecturaIds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), id.uuidString, -1, SQLITE_TRANSIENT)
        }

        var result: [UUID: ChunkMeta] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let uuid = UUID(uuidString: String(cString: idPtr)),
                  let urlPtr = sqlite3_column_text(stmt, 1) else { continue }

            let pageURL = String(cString: urlPtr)
            var sectionHierarchy: [String] = []
            if let hierarchyPtr = sqlite3_column_text(stmt, 2),
               let data = String(cString: hierarchyPtr).data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                sectionHierarchy = array
            }
            let positionInDoc = Float(sqlite3_column_double(stmt, 3))

            result[uuid] = ChunkMeta(pageURL: pageURL, sectionHierarchy: sectionHierarchy, positionInDoc: positionInDoc)
        }
        return result
    }

    func getPageMetadata(urls: [String]) throws -> [String: PageMeta] {
        try ensureInitialized()
        guard !urls.isEmpty else { return [:] }

        let placeholders = urls.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT url, title, domain, categories
            FROM indexed_pages WHERE url IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        for (i, url) in urls.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), url, -1, SQLITE_TRANSIENT)
        }

        var result: [String: PageMeta] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlPtr = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlPtr)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let domain = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            var categories: [String] = []
            if let catPtr = sqlite3_column_text(stmt, 3),
               let data = String(cString: catPtr).data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                categories = array
            }
            result[url] = PageMeta(url: url, title: title, domain: domain, categories: categories)
        }
        return result
    }

    func searchKeywordMatches(query: String, limit: Int = 50) throws -> [PageKeywordMatch] {
        try ensureInitialized()

        let ftsQuery = makeFTSQuery(query)
        guard !ftsQuery.isEmpty else { return [] }

        let sql = """
            SELECT p.url, p.title, p.full_text, p.categories, bm25(indexed_pages_fts)
            FROM indexed_pages p
            JOIN indexed_pages_fts ON indexed_pages_fts.rowid = p.rowid
            WHERE indexed_pages_fts MATCH ?
            ORDER BY bm25(indexed_pages_fts)
            LIMIT ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var matches: [PageKeywordMatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlPtr = sqlite3_column_text(stmt, 0) else { continue }

            let url = String(cString: urlPtr)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let fullText = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            var categories: [String] = []
            if let catPtr = sqlite3_column_text(stmt, 3),
               let data = String(cString: catPtr).data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                categories = array
            }
            let bm25Score = sqlite3_column_double(stmt, 4)

            matches.append(PageKeywordMatch(
                url: url,
                title: title,
                fullText: fullText,
                categories: categories,
                bm25Score: bm25Score
            ))
        }

        return matches
    }

    /// Delete all chunk mappings for a page, returning VecturaKit IDs to delete
    func deleteChunksForPage(url: String) throws -> [UUID] {
        try ensureInitialized()

        // First collect the VecturaKit IDs
        let selectSQL = "SELECT vectura_id FROM chunk_map WHERE page_url = ?"
        var selectStmt: OpaquePointer?
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(selectStmt, 1, url, -1, SQLITE_TRANSIENT)

        var ids: [UUID] = []
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(selectStmt, 0),
               let uuid = UUID(uuidString: String(cString: ptr)) {
                ids.append(uuid)
            }
        }

        // Then delete
        let deleteSQL = "DELETE FROM chunk_map WHERE page_url = ?"
        var deleteStmt: OpaquePointer?
        defer { sqlite3_finalize(deleteStmt) }

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(deleteStmt, 1, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }

        return ids
    }

    func getChunkCount() throws -> Int {
        try ensureInitialized()
        let sql = "SELECT count(*) FROM chunk_map"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SearchDBError.executeFailed("Failed to get chunk count")
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func getPageCount() throws -> Int {
        try ensureInitialized()
        let sql = "SELECT count(*) FROM indexed_pages"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SearchDBError.executeFailed("Failed to get page count")
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func clearAll() throws {
        try ensureInitialized()
        try execute("DELETE FROM chunk_map")
        try execute("DELETE FROM indexed_pages")
    }

    // MARK: - Private

    private func openDatabase() throws {
        let dir = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath.path, &db, flags, nil) != SQLITE_OK {
            throw SearchDBError.failedToOpen(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    private func createSchema() throws {
        let hadKeywordIndex = try objectExists(type: "table", name: "indexed_pages_fts")
        let migrationState = try runMigrations()

        try execute("""
            CREATE TABLE IF NOT EXISTS indexed_pages (
                url TEXT PRIMARY KEY,
                title TEXT,
                domain TEXT,
                content_hash TEXT NOT NULL,
                categories TEXT,
                full_text TEXT,
                indexed_at INTEGER NOT NULL
            )
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS chunk_map (
                vectura_id TEXT PRIMARY KEY,
                page_url TEXT NOT NULL,
                section_hierarchy TEXT,
                position_in_doc REAL,
                FOREIGN KEY (page_url) REFERENCES indexed_pages(url) ON DELETE CASCADE
            )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_chunk_map_url ON chunk_map(page_url)")
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS indexed_pages_fts USING fts5(
                title,
                full_text,
                content='indexed_pages',
                content_rowid='rowid',
                tokenize='porter unicode61'
            )
        """)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS indexed_pages_fts_insert AFTER INSERT ON indexed_pages BEGIN
                INSERT INTO indexed_pages_fts(rowid, title, full_text)
                VALUES (new.rowid, new.title, new.full_text);
            END
        """)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS indexed_pages_fts_update AFTER UPDATE OF title, full_text ON indexed_pages BEGIN
                INSERT INTO indexed_pages_fts(indexed_pages_fts, rowid, title, full_text)
                VALUES ('delete', old.rowid, old.title, old.full_text);
                INSERT INTO indexed_pages_fts(rowid, title, full_text)
                VALUES (new.rowid, new.title, new.full_text);
            END
        """)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS indexed_pages_fts_delete AFTER DELETE ON indexed_pages BEGIN
                INSERT INTO indexed_pages_fts(indexed_pages_fts, rowid, title, full_text)
                VALUES ('delete', old.rowid, old.title, old.full_text);
            END
        """)

        if !hadKeywordIndex || migrationState.needsKeywordIndexRebuild {
            try execute("INSERT INTO indexed_pages_fts(indexed_pages_fts) VALUES ('rebuild')")
        }
    }

    private struct MigrationState {
        var needsKeywordIndexRebuild = false
    }

    private func runMigrations() throws -> MigrationState {
        let columns: Set<String> = {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, "PRAGMA table_info(indexed_pages)", -1, &stmt, nil) == SQLITE_OK else {
                return []
            }

            var names = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 1) {
                    names.insert(String(cString: namePtr))
                }
            }
            return names
        }()

        var state = MigrationState()
        guard !columns.isEmpty else { return state }

        if !columns.contains("full_text") {
            try execute("ALTER TABLE indexed_pages ADD COLUMN full_text TEXT")
            state.needsKeywordIndexRebuild = true
        }

        return state
    }

    private func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if result != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            throw SearchDBError.executeFailed(error)
        }
    }

    private func objectExists(type: String, name: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)

        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func makeFTSQuery(_ query: String) -> String {
        let terms = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { term -> String in
                Self.ftsSanitizeRegex.stringByReplacingMatches(
                    in: term,
                    options: [],
                    range: NSRange(term.startIndex..., in: term),
                    withTemplate: ""
                )
            }
            .filter { !$0.isEmpty }
            .prefix(8)

        guard !terms.isEmpty else { return "" }
        if terms.count == 1 {
            return String(terms[0])
        }

        let phrase = "\"\(terms.joined(separator: " "))\""
        let allTerms = terms.joined(separator: " ")
        return "\(phrase) OR \(allTerms)"
    }
}
