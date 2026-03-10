import Foundation
import SQLite3

/// Unified SQLite store for reading-list metadata, summaries, and semantic page metadata.
actor PageIndexStore: SummaryRepository, SemanticPageIndexingStore {
    static let shared: PageIndexStore = {
        do {
            let store = try PageIndexStore.makeSharedStore()
            Task { try await store.initialize() }
            return store
        } catch {
            Log.Search.error("Failed to create PageIndexStore: \(error.localizedDescription)")
            return PageIndexStore(inMemory: true)
        }
    }()

    private static let defaultDBPath = FileManager.appSupportDirectory.appendingPathComponent("page_index.db")
    private static let defaultReadingListPath = FileManager.appSupportDirectory.appendingPathComponent("semantic_search.db")
    private static let defaultMetadataPath = FileManager.appSupportDirectory.appendingPathComponent("semantic_search_meta.db")

    private static let ftsSanitizeRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "[\"'\\-\\+\\*\\(\\)\\{\\}\\[\\]\\^\\~\\:\\@\\#\\$\\%\\&]",
            options: []
        ) else {
            fatalError("PageIndexStore: FTS sanitize regex is invalid")
        }
        return regex
    }()

    private var db: OpaquePointer?
    private let dbPath: URL
    private let legacyReadingListPath: URL?
    private let legacyMetadataPath: URL?
    private var isInitialized = false

    private(set) var isDegraded = false

    init(
        dbPath: URL,
        legacyReadingListPath: URL? = nil,
        legacyMetadataPath: URL? = nil
    ) throws {
        self.dbPath = dbPath
        self.legacyReadingListPath = legacyReadingListPath
        self.legacyMetadataPath = legacyMetadataPath
    }

    private init(inMemory: Bool) {
        self.dbPath = URL(fileURLWithPath: ":memory:")
        self.legacyReadingListPath = nil
        self.legacyMetadataPath = nil
        self.isDegraded = inMemory
    }

    private static func makeSharedStore() throws -> PageIndexStore {
        try PageIndexStore(
            dbPath: defaultDBPath,
            legacyReadingListPath: defaultReadingListPath,
            legacyMetadataPath: defaultMetadataPath
        )
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func initialize() throws {
        guard !isInitialized else { return }

        do {
            try openDatabase()
            try verifyIntegrity()
        } catch {
            Log.Search.error("PageIndexStore: on-disk open/integrity failed: \(error.localizedDescription), falling back to in-memory")
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
            isDegraded = true
            try openInMemoryDatabase()
        }

        try createSchema()
        try migrateLegacyStoresIfNeeded()
        isInitialized = true
    }

    func ensureInitialized() throws {
        try initialize()
    }

    func checkIntegrity() throws {
        try verifyIntegrity()
    }

    func close() {
        guard let connection = db else { return }
        sqlite3_wal_checkpoint_v2(connection, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close(connection)
        db = nil
        isInitialized = false
    }

    func vacuum() throws {
        try execute("VACUUM")
    }

    // MARK: - Reading List Operations

    func upsertPage(url: URL, title: String?, workspaceID: UUID? = nil) throws -> Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        let domain = url.host ?? ""
        let sql = """
            INSERT INTO pages (
                url, title, domain, first_visited_at, last_visited_at, visit_count, workspace_id
            ) VALUES (?, ?, ?, ?, ?, 1, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = COALESCE(excluded.title, pages.title),
                domain = CASE
                    WHEN pages.domain IS NULL OR pages.domain = '' THEN excluded.domain
                    ELSE pages.domain
                END,
                last_visited_at = excluded.last_visited_at,
                visit_count = pages.visit_count + 1,
                workspace_id = COALESCE(excluded.workspace_id, pages.workspace_id)
            RETURNING id
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, url.absoluteString, -1, SQLITE_TRANSIENT)
        bindNullableText(title, at: 2, into: stmt)
        sqlite3_bind_text(stmt, 3, domain, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, now)
        sqlite3_bind_int64(stmt, 5, now)
        bindNullableText(workspaceID?.uuidString, at: 6, into: stmt)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_column_int64(stmt, 0)
    }

    func toggleSaved(url: String, title: String? = nil) throws -> Bool {
        guard let pageURL = URL(string: url) else {
            return false
        }

        let checkSQL = "SELECT is_saved FROM pages WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let currentState = sqlite3_column_int(stmt, 0) != 0
            let newState = !currentState
            try setSaved(url: url, saved: newState)
            return newState
        }

        _ = try upsertPage(url: pageURL, title: title)
        try setSaved(url: url, saved: true)
        return true
    }

    func setSaved(url: String, saved: Bool) throws {
        let sql = "UPDATE pages SET is_saved = ?, saved_at = ? WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, saved ? 1 : 0)
        if saved {
            sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func isSaved(url: String) throws -> Bool {
        let sql = "SELECT is_saved FROM pages WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int(stmt, 0) != 0
    }

    func getSavedPages(limit: Int = 100) throws -> [SavedPageRecord] {
        let sql = """
            SELECT id, url, title, domain, summary, saved_at, last_visited_at
            FROM pages
            WHERE is_saved = 1
            ORDER BY saved_at DESC
            LIMIT ?
        """
        return try fetchSavedPageRecords(sql: sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }
    }

    func searchSavedPages(query: String, limit: Int = 50) throws -> [SavedPageRecord] {
        let ftsQuery = makeFTSQuery(query)
        guard !ftsQuery.isEmpty else {
            return try getSavedPages(limit: limit)
        }

        let sql = """
            SELECT p.id, p.url, p.title, p.domain, p.summary, p.saved_at, p.last_visited_at
            FROM pages p
            JOIN pages_fts fts ON fts.rowid = p.id
            WHERE p.is_saved = 1 AND pages_fts MATCH ?
            ORDER BY bm25(pages_fts)
            LIMIT ?
        """

        return try fetchSavedPageRecords(sql: sql) { stmt in
            sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
    }

    func updateSummary(url: String, summary: String) throws {
        let sql = "UPDATE pages SET summary = ? WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, summary, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func clearAllSummaries() throws {
        try execute("UPDATE pages SET summary = NULL WHERE is_saved = 1")
    }

    func getSavedPagesWithoutSummary(limit: Int = 20) throws -> [SavedPageRecord] {
        let sql = """
            SELECT id, url, title, domain, summary, saved_at, last_visited_at
            FROM pages
            WHERE is_saved = 1 AND (summary IS NULL OR summary = '')
            ORDER BY saved_at DESC
            LIMIT ?
        """
        return try fetchSavedPageRecords(sql: sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }
    }

    func clearReadingList() throws {
        try execute("UPDATE pages SET is_saved = 0, saved_at = NULL WHERE is_saved = 1")
    }

    func clearAllData() throws {
        try execute("DELETE FROM chunk_map")
        try execute("DELETE FROM pages")
        try rebuildFTS()
    }

    // MARK: - Semantic Search Operations

    func getPageHash(url: String) throws -> String? {
        let sql = "SELECT content_hash FROM pages WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let value = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: value)
    }

    func upsertPage(
        url: String,
        title: String?,
        domain: String,
        contentHash: String,
        categories: [String],
        fullText: String?
    ) throws {
        let categoriesJSON = encodeJSONString(categories) ?? "[]"
        try upsertIndexedPage(
            url: url,
            title: title,
            domain: domain,
            contentHash: contentHash,
            categoriesJSON: categoriesJSON,
            fullText: fullText,
            indexedAt: Int64(Date().timeIntervalSince1970)
        )
    }

    func addChunkMapping(vecturaId: UUID, pageURL: String, sectionHierarchy: [String], positionInDoc: Float) throws {
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
        bindNullableText(encodeJSONString(sectionHierarchy), at: 3, into: stmt)
        sqlite3_bind_double(stmt, 4, Double(positionInDoc))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func getChunkMetadata(vecturaIds: [UUID]) throws -> [UUID: ChunkMeta] {
        guard !vecturaIds.isEmpty else { return [:] }
        let placeholders = vecturaIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT vectura_id, page_url, section_hierarchy, position_in_doc
            FROM chunk_map
            WHERE vectura_id IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        for (index, id) in vecturaIds.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), id.uuidString, -1, SQLITE_TRANSIENT)
        }

        var results: [UUID: ChunkMeta] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let vecturaIDText = sqlite3_column_text(stmt, 0),
                let vecturaID = UUID(uuidString: String(cString: vecturaIDText)),
                let pageURLText = sqlite3_column_text(stmt, 1)
            else {
                continue
            }

            results[vecturaID] = ChunkMeta(
                pageURL: String(cString: pageURLText),
                sectionHierarchy: decodeStringArray(from: sqlite3_column_text(stmt, 2)),
                positionInDoc: Float(sqlite3_column_double(stmt, 3))
            )
        }
        return results
    }

    func getPageMetadata(urls: [String]) throws -> [String: PageMeta] {
        guard !urls.isEmpty else { return [:] }
        let placeholders = urls.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT url, title, domain, categories
            FROM pages
            WHERE url IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        for (index, url) in urls.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), url, -1, SQLITE_TRANSIENT)
        }

        var results: [String: PageMeta] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlText)
            results[url] = PageMeta(
                url: url,
                title: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
                domain: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
                categories: decodeStringArray(from: sqlite3_column_text(stmt, 3))
            )
        }
        return results
    }

    func searchKeywordMatches(query: String, limit: Int = 50) throws -> [PageKeywordMatch] {
        let ftsQuery = makeFTSQuery(query)
        guard !ftsQuery.isEmpty else { return [] }

        let sql = """
            SELECT p.url, p.title, p.full_text, p.categories, bm25(pages_fts)
            FROM pages p
            JOIN pages_fts ON pages_fts.rowid = p.id
            WHERE (p.content_hash IS NOT NULL OR (p.full_text IS NOT NULL AND p.full_text != ''))
              AND pages_fts MATCH ?
            ORDER BY bm25(pages_fts)
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
            guard let urlText = sqlite3_column_text(stmt, 0) else { continue }
            matches.append(
                PageKeywordMatch(
                    url: String(cString: urlText),
                    title: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
                    fullText: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                    categories: decodeStringArray(from: sqlite3_column_text(stmt, 3)),
                    bm25Score: sqlite3_column_double(stmt, 4)
                )
            )
        }
        return matches
    }

    func deleteChunksForPage(url: String) throws -> [UUID] {
        let selectSQL = "SELECT vectura_id FROM chunk_map WHERE page_url = ?"
        var selectStmt: OpaquePointer?
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(selectStmt, 1, url, -1, SQLITE_TRANSIENT)

        var ids: [UUID] = []
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            if let value = sqlite3_column_text(selectStmt, 0),
               let id = UUID(uuidString: String(cString: value)) {
                ids.append(id)
            }
        }

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
        try scalarCount(sql: "SELECT count(*) FROM chunk_map")
    }

    func getPageCount() throws -> Int {
        try scalarCount(sql: "SELECT count(*) FROM pages WHERE content_hash IS NOT NULL")
    }

    func clearAll() throws {
        try execute("DELETE FROM chunk_map")
        try execute("""
            UPDATE pages
            SET content_hash = NULL,
                categories = NULL,
                full_text = NULL,
                indexed_at = NULL
        """)
        try rebuildFTS()
    }

    // MARK: - Setup

    private func openDatabase() throws {
        let directory = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath.path, &db, flags, nil) != SQLITE_OK {
            throw SearchDBError.failedToOpen(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    private func openInMemoryDatabase() throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(":memory:", &db, flags, nil) != SQLITE_OK {
            throw SearchDBError.failedToOpen(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA foreign_keys = ON")
    }

    private func verifyIntegrity() throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed("integrity_check prepare failed")
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SearchDBError.executeFailed("integrity_check returned no result")
        }

        let result = String(cString: sqlite3_column_text(stmt, 0))
        guard result == "ok" else {
            throw SearchDBError.executeFailed("integrity_check failed: \(result)")
        }
    }

    private func createSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS app_metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)

        if try objectExists(type: "table", name: "pages") {
            try migratePagesSchemaIfNeeded()
        } else {
            try execute(Self.createPagesTableSQL)
        }

        try execute("CREATE INDEX IF NOT EXISTS idx_pages_domain ON pages(domain)")
        try execute("CREATE INDEX IF NOT EXISTS idx_pages_last_visited ON pages(last_visited_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_pages_workspace ON pages(workspace_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_pages_saved ON pages(is_saved, saved_at DESC) WHERE is_saved = 1")
        try execute("CREATE INDEX IF NOT EXISTS idx_pages_content_hash ON pages(content_hash)")

        try execute("""
            CREATE TABLE IF NOT EXISTS chunk_map (
                vectura_id TEXT PRIMARY KEY,
                page_url TEXT NOT NULL,
                section_hierarchy TEXT,
                position_in_doc REAL,
                FOREIGN KEY (page_url) REFERENCES pages(url) ON DELETE CASCADE
            )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_chunk_map_url ON chunk_map(page_url)")

        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS pages_fts USING fts5(
                title,
                summary,
                full_text,
                content='pages',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS pages_fts_insert AFTER INSERT ON pages BEGIN
                INSERT INTO pages_fts(rowid, title, summary, full_text)
                VALUES (new.id, new.title, new.summary, new.full_text);
            END
        """)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS pages_fts_update AFTER UPDATE OF title, summary, full_text ON pages BEGIN
                INSERT INTO pages_fts(pages_fts, rowid, title, summary, full_text)
                VALUES ('delete', old.id, old.title, old.summary, old.full_text);
                INSERT INTO pages_fts(rowid, title, summary, full_text)
                VALUES (new.id, new.title, new.summary, new.full_text);
            END
        """)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS pages_fts_delete AFTER DELETE ON pages BEGIN
                INSERT INTO pages_fts(pages_fts, rowid, title, summary, full_text)
                VALUES ('delete', old.id, old.title, old.summary, old.full_text);
            END
        """)

        try rebuildFTS()
    }

    private func migratePagesSchemaIfNeeded() throws {
        let columns = try tableColumns(in: "pages")
        if !columns.contains("domain") {
            try execute("ALTER TABLE pages ADD COLUMN domain TEXT")
        }
        if !columns.contains("full_text") {
            try execute("ALTER TABLE pages ADD COLUMN full_text TEXT")
        }
        if !columns.contains("summary") {
            try execute("ALTER TABLE pages ADD COLUMN summary TEXT")
        }
        if !columns.contains("first_visited_at") {
            try execute("ALTER TABLE pages ADD COLUMN first_visited_at INTEGER NOT NULL DEFAULT 0")
        }
        if !columns.contains("last_visited_at") {
            try execute("ALTER TABLE pages ADD COLUMN last_visited_at INTEGER NOT NULL DEFAULT 0")
        }
        if !columns.contains("visit_count") {
            try execute("ALTER TABLE pages ADD COLUMN visit_count INTEGER DEFAULT 1")
        }
        if !columns.contains("workspace_id") {
            try execute("ALTER TABLE pages ADD COLUMN workspace_id TEXT")
        }
        if !columns.contains("is_saved") {
            try execute("ALTER TABLE pages ADD COLUMN is_saved INTEGER DEFAULT 0")
        }
        if !columns.contains("saved_at") {
            try execute("ALTER TABLE pages ADD COLUMN saved_at INTEGER")
        }
        if !columns.contains("content_hash") {
            try execute("ALTER TABLE pages ADD COLUMN content_hash TEXT")
        }
        if !columns.contains("categories") {
            try execute("ALTER TABLE pages ADD COLUMN categories TEXT")
        }
        if !columns.contains("indexed_at") {
            try execute("ALTER TABLE pages ADD COLUMN indexed_at INTEGER")
        }

        try backfillMissingDomains()
    }

    private func migrateLegacyStoresIfNeeded() throws {
        guard legacyReadingListPath != nil || legacyMetadataPath != nil else { return }

        let migrationKey = "legacy-page-index-import-v1"
        if try metadataValue(for: migrationKey) == "done" {
            return
        }

        var migratedAnything = false
        if let legacyReadingListPath, legacyReadingListPath.standardizedFileURL != dbPath.standardizedFileURL {
            migratedAnything = try migrateLegacyReadingList(from: legacyReadingListPath) || migratedAnything
        }
        if let legacyMetadataPath, legacyMetadataPath.standardizedFileURL != dbPath.standardizedFileURL {
            migratedAnything = try migrateLegacyMetadata(from: legacyMetadataPath) || migratedAnything
        }

        if migratedAnything {
            try rebuildFTS()
        }
        try setMetadataValue("done", for: migrationKey)
    }

    private func migrateLegacyReadingList(from path: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else { return false }

        let connection = try openLegacyConnection(at: path)
        defer { sqlite3_close(connection) }

        guard try objectExists(connection: connection, type: "table", name: "pages") else {
            return false
        }

        let columns = try tableColumns(connection: connection, in: "pages")
        let sql = """
            SELECT
                url,
                \(columns.contains("title") ? "title" : "NULL AS title"),
                \(columns.contains("domain") ? "domain" : "NULL AS domain"),
                \(columns.contains("full_text") ? "full_text" : "NULL AS full_text"),
                \(columns.contains("summary") ? "summary" : "NULL AS summary"),
                \(columns.contains("first_visited_at") ? "first_visited_at" : "0 AS first_visited_at"),
                \(columns.contains("last_visited_at") ? "last_visited_at" : "0 AS last_visited_at"),
                \(columns.contains("visit_count") ? "visit_count" : "1 AS visit_count"),
                \(columns.contains("workspace_id") ? "workspace_id" : "NULL AS workspace_id"),
                \(columns.contains("is_saved") ? "is_saved" : "0 AS is_saved"),
                \(columns.contains("saved_at") ? "saved_at" : "NULL AS saved_at")
            FROM pages
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(connection, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(connection)))
        }

        var migratedAnything = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlText)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let domain = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let fullText = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let summary = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let firstVisitedAt = sqlite3_column_int64(stmt, 5)
            let lastVisitedAt = sqlite3_column_int64(stmt, 6)
            let visitCount = max(1, Int(sqlite3_column_int(stmt, 7)))
            let workspaceID = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
            let isSaved = sqlite3_column_int(stmt, 9) != 0
            let savedAt = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 10)

            try upsertReadingListPage(
                url: url,
                title: title,
                domain: resolvedDomain(fallback: domain, from: url),
                fullText: fullText,
                summary: summary,
                firstVisitedAt: firstVisitedAt,
                lastVisitedAt: lastVisitedAt,
                visitCount: visitCount,
                workspaceID: workspaceID,
                isSaved: isSaved,
                savedAt: savedAt
            )
            migratedAnything = true
        }

        return migratedAnything
    }

    private func migrateLegacyMetadata(from path: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else { return false }

        let connection = try openLegacyConnection(at: path)
        defer { sqlite3_close(connection) }

        guard try objectExists(connection: connection, type: "table", name: "indexed_pages") else {
            return false
        }

        let pageColumns = try tableColumns(connection: connection, in: "indexed_pages")
        let pageSQL = """
            SELECT
                url,
                \(pageColumns.contains("title") ? "title" : "NULL AS title"),
                \(pageColumns.contains("domain") ? "domain" : "NULL AS domain"),
                \(pageColumns.contains("content_hash") ? "content_hash" : "NULL AS content_hash"),
                \(pageColumns.contains("categories") ? "categories" : "NULL AS categories"),
                \(pageColumns.contains("full_text") ? "full_text" : "NULL AS full_text"),
                \(pageColumns.contains("indexed_at") ? "indexed_at" : "0 AS indexed_at")
            FROM indexed_pages
        """

        var pageStmt: OpaquePointer?
        defer { sqlite3_finalize(pageStmt) }

        guard sqlite3_prepare_v2(connection, pageSQL, -1, &pageStmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(connection)))
        }

        var migratedAnything = false
        while sqlite3_step(pageStmt) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(pageStmt, 0) else { continue }
            let url = String(cString: urlText)
            let title = sqlite3_column_text(pageStmt, 1).map { String(cString: $0) }
            let domain = resolvedDomain(
                fallback: sqlite3_column_text(pageStmt, 2).map { String(cString: $0) },
                from: url
            )
            let contentHash = sqlite3_column_text(pageStmt, 3).map { String(cString: $0) }
            let categoriesJSON = sqlite3_column_text(pageStmt, 4).map { String(cString: $0) } ?? "[]"
            let fullText = sqlite3_column_text(pageStmt, 5).map { String(cString: $0) }
            let indexedAt = sqlite3_column_int64(pageStmt, 6)

            try upsertIndexedPage(
                url: url,
                title: title,
                domain: domain,
                contentHash: contentHash,
                categoriesJSON: categoriesJSON,
                fullText: fullText,
                indexedAt: indexedAt > 0 ? indexedAt : Int64(Date().timeIntervalSince1970)
            )
            migratedAnything = true
        }

        if try objectExists(connection: connection, type: "table", name: "chunk_map") {
            let chunkSQL = """
                SELECT vectura_id, page_url, section_hierarchy, position_in_doc
                FROM chunk_map
            """
            var chunkStmt: OpaquePointer?
            defer { sqlite3_finalize(chunkStmt) }

            guard sqlite3_prepare_v2(connection, chunkSQL, -1, &chunkStmt, nil) == SQLITE_OK else {
                throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(connection)))
            }

            while sqlite3_step(chunkStmt) == SQLITE_ROW {
                guard
                    let vecturaIDText = sqlite3_column_text(chunkStmt, 0),
                    let pageURLText = sqlite3_column_text(chunkStmt, 1)
                else {
                    continue
                }

                let vecturaID = String(cString: vecturaIDText)
                let pageURL = String(cString: pageURLText)
                let hierarchyJSON = sqlite3_column_text(chunkStmt, 2).map { String(cString: $0) }
                let position = sqlite3_column_double(chunkStmt, 3)

                try insertChunkMapping(
                    vecturaID: vecturaID,
                    pageURL: pageURL,
                    sectionHierarchyJSON: hierarchyJSON,
                    positionInDoc: Float(position)
                )
                migratedAnything = true
            }
        }

        return migratedAnything
    }

    // MARK: - Private Helpers

    private static let createPagesTableSQL = """
        CREATE TABLE IF NOT EXISTS pages (
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
            saved_at INTEGER,
            content_hash TEXT,
            categories TEXT,
            indexed_at INTEGER
        )
    """

    private func fetchSavedPageRecords(
        sql: String,
        binder: (OpaquePointer?) -> Void
    ) throws -> [SavedPageRecord] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        binder(stmt)

        var pages: [SavedPageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(stmt, 1),
                  let url = URL(string: String(cString: urlText)) else {
                continue
            }

            pages.append(
                SavedPageRecord(
                    id: sqlite3_column_int64(stmt, 0),
                    url: url,
                    title: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                    domain: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "",
                    summary: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                    savedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 5))),
                    lastVisitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 6)))
                )
            )
        }
        return pages
    }

    private func upsertReadingListPage(
        url: String,
        title: String?,
        domain: String,
        fullText: String?,
        summary: String?,
        firstVisitedAt: Int64,
        lastVisitedAt: Int64,
        visitCount: Int,
        workspaceID: String?,
        isSaved: Bool,
        savedAt: Int64?
    ) throws {
        let sql = """
            INSERT INTO pages (
                url, title, domain, full_text, summary, first_visited_at, last_visited_at,
                visit_count, workspace_id, is_saved, saved_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = COALESCE(excluded.title, pages.title),
                domain = CASE
                    WHEN pages.domain IS NULL OR pages.domain = '' THEN excluded.domain
                    ELSE pages.domain
                END,
                full_text = COALESCE(excluded.full_text, pages.full_text),
                summary = COALESCE(excluded.summary, pages.summary),
                first_visited_at = CASE
                    WHEN pages.first_visited_at = 0 THEN excluded.first_visited_at
                    WHEN excluded.first_visited_at = 0 THEN pages.first_visited_at
                    ELSE MIN(pages.first_visited_at, excluded.first_visited_at)
                END,
                last_visited_at = MAX(pages.last_visited_at, excluded.last_visited_at),
                visit_count = MAX(pages.visit_count, excluded.visit_count),
                workspace_id = COALESCE(excluded.workspace_id, pages.workspace_id),
                is_saved = MAX(pages.is_saved, excluded.is_saved),
                saved_at = CASE
                    WHEN pages.saved_at IS NULL THEN excluded.saved_at
                    WHEN excluded.saved_at IS NULL THEN pages.saved_at
                    ELSE MAX(pages.saved_at, excluded.saved_at)
                END
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)
        bindNullableText(title, at: 2, into: stmt)
        sqlite3_bind_text(stmt, 3, domain, -1, SQLITE_TRANSIENT)
        bindNullableText(fullText, at: 4, into: stmt)
        bindNullableText(summary, at: 5, into: stmt)
        sqlite3_bind_int64(stmt, 6, firstVisitedAt)
        sqlite3_bind_int64(stmt, 7, lastVisitedAt)
        sqlite3_bind_int(stmt, 8, Int32(max(1, visitCount)))
        bindNullableText(workspaceID, at: 9, into: stmt)
        sqlite3_bind_int(stmt, 10, isSaved ? 1 : 0)
        if let savedAt {
            sqlite3_bind_int64(stmt, 11, savedAt)
        } else {
            sqlite3_bind_null(stmt, 11)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func upsertIndexedPage(
        url: String,
        title: String?,
        domain: String,
        contentHash: String?,
        categoriesJSON: String,
        fullText: String?,
        indexedAt: Int64
    ) throws {
        let sql = """
            INSERT INTO pages (
                url, title, domain, content_hash, categories, full_text, indexed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = COALESCE(excluded.title, pages.title),
                domain = CASE
                    WHEN pages.domain IS NULL OR pages.domain = '' THEN excluded.domain
                    ELSE pages.domain
                END,
                content_hash = COALESCE(excluded.content_hash, pages.content_hash),
                categories = COALESCE(excluded.categories, pages.categories),
                full_text = COALESCE(excluded.full_text, pages.full_text),
                indexed_at = CASE
                    WHEN pages.indexed_at IS NULL THEN excluded.indexed_at
                    ELSE MAX(pages.indexed_at, excluded.indexed_at)
                END
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)
        bindNullableText(title, at: 2, into: stmt)
        sqlite3_bind_text(stmt, 3, domain, -1, SQLITE_TRANSIENT)
        bindNullableText(contentHash, at: 4, into: stmt)
        sqlite3_bind_text(stmt, 5, categoriesJSON, -1, SQLITE_TRANSIENT)
        bindNullableText(fullText, at: 6, into: stmt)
        sqlite3_bind_int64(stmt, 7, indexedAt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func insertChunkMapping(
        vecturaID: String,
        pageURL: String,
        sectionHierarchyJSON: String?,
        positionInDoc: Float
    ) throws {
        let sql = """
            INSERT OR REPLACE INTO chunk_map (vectura_id, page_url, section_hierarchy, position_in_doc)
            VALUES (?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, vecturaID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, pageURL, -1, SQLITE_TRANSIENT)
        bindNullableText(sectionHierarchyJSON, at: 3, into: stmt)
        sqlite3_bind_double(stmt, 4, Double(positionInDoc))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func setMetadataValue(_ value: String, for key: String) throws {
        let sql = """
            INSERT INTO app_metadata (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func metadataValue(for key: String) throws -> String? {
        let sql = "SELECT value FROM app_metadata WHERE key = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let value = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: value)
    }

    private func backfillMissingDomains() throws {
        let sql = "SELECT id, url FROM pages WHERE domain IS NULL OR domain = ''"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            guard let urlText = sqlite3_column_text(stmt, 1) else { continue }
            let domain = URL(string: String(cString: urlText))?.host ?? ""
            try updateDomain(domain, forPageID: id)
        }
    }

    private func updateDomain(_ domain: String, forPageID pageID: Int64) throws {
        let sql = "UPDATE pages SET domain = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, domain, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, pageID)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func rebuildFTS() throws {
        try execute("INSERT INTO pages_fts(pages_fts) VALUES ('rebuild')")
    }

    private func scalarCount(sql: String) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SearchDBError.executeFailed("Failed to evaluate count query")
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw SearchDBError.executeFailed(message)
        }
    }

    private func objectExists(type: String, name: String) throws -> Bool {
        try objectExists(connection: db, type: type, name: name)
    }

    private func objectExists(connection: OpaquePointer?, type: String, name: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(connection, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(connection)))
        }
        sqlite3_bind_text(stmt, 1, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func tableColumns(in table: String) throws -> Set<String> {
        try tableColumns(connection: db, in: table)
    }

    private func tableColumns(connection: OpaquePointer?, in table: String) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table))"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(connection, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(connection)))
        }

        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let value = sqlite3_column_text(stmt, 1) {
                names.insert(String(cString: value))
            }
        }
        return names
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

    private func bindNullableText(_ value: String?, at index: Int32, into stmt: OpaquePointer?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func resolvedDomain(fallback: String?, from url: String) -> String {
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return URL(string: url)?.host ?? ""
    }

    private func encodeJSONString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private func decodeStringArray(from text: UnsafePointer<UInt8>?) -> [String] {
        guard let text,
              let data = String(cString: text).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }

    private func openLegacyConnection(at path: URL) throws -> OpaquePointer? {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path.path, &connection, flags, nil) != SQLITE_OK {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(connection)
            throw SearchDBError.failedToOpen(message)
        }
        sqlite3_busy_timeout(connection, 5000)
        return connection
    }
}
