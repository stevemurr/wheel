import Foundation
import SQLite3
import SqliteVec

/// SQLite-based search database with vector search support
actor SearchDatabase {
    private var db: OpaquePointer?
    private let dbPath: URL
    private let embeddingDimension: Int32
    private var isInitialized = false

    init(embeddingDimension: Int = 1536) throws {
        self.embeddingDimension = Int32(embeddingDimension)

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("WheelBrowser")

        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.dbPath = appSupport.appendingPathComponent("semantic_search.db")
    }

    /// Must be called after init to complete setup
    func initialize() throws {
        guard !isInitialized else { return }
        print("SearchDatabase: Opening database at \(dbPath.path)")
        try openDatabase()
        print("SearchDatabase: Database opened, running integrity check...")
        try verifyIntegrity()
        print("SearchDatabase: Integrity OK, registering sqlite-vec")
        try registerSqliteVec()
        print("SearchDatabase: sqlite-vec registered, creating schema")
        try createSchema()
        print("SearchDatabase: Schema created, verifying integrity again...")
        try verifyIntegrity()
        print("SearchDatabase: Schema created successfully")
        isInitialized = true
    }

    func checkIntegrity() throws {
        try verifyIntegrity()
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

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    /// Explicitly close the database connection
    func close() {
        guard let connection = db else { return }
        // Checkpoint WAL before closing to ensure data is flushed
        sqlite3_wal_checkpoint_v2(connection, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close(connection)
        db = nil
        isInitialized = false
    }

    // MARK: - Setup

    private func openDatabase() throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        if sqlite3_open_v2(dbPath.path, &db, flags, nil) != SQLITE_OK {
            throw SearchDBError.failedToOpen(String(cString: sqlite3_errmsg(db)))
        }

        // Set busy timeout to 5 seconds to handle brief locking scenarios
        sqlite3_busy_timeout(db, 5000)

        // WAL mode for better concurrent performance
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    private func registerSqliteVec() throws {
        guard let db = db else { throw SearchDBError.failedToOpen("No connection") }
        try SqliteVec.register(db: db)
    }

    private func createSchema() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS pages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL UNIQUE,
            title TEXT,
            domain TEXT,
            full_text TEXT,
            summary TEXT,
            title_embedding BLOB,
            summary_embedding BLOB,
            first_visited_at INTEGER NOT NULL,
            last_visited_at INTEGER NOT NULL,
            visit_count INTEGER DEFAULT 1,
            workspace_id TEXT,
            content_extracted INTEGER DEFAULT 0,
            summary_generated INTEGER DEFAULT 0,
            embeddings_generated INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            page_id INTEGER NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            chunk_index INTEGER NOT NULL,
            text TEXT NOT NULL,
            embedding BLOB,
            UNIQUE(page_id, chunk_index)
        );

        CREATE INDEX IF NOT EXISTS idx_pages_domain ON pages(domain);
        CREATE INDEX IF NOT EXISTS idx_pages_last_visited ON pages(last_visited_at DESC);
        CREATE INDEX IF NOT EXISTS idx_pages_workspace ON pages(workspace_id);
        CREATE INDEX IF NOT EXISTS idx_pages_pending ON pages(embeddings_generated) WHERE embeddings_generated = 0;
        CREATE INDEX IF NOT EXISTS idx_chunks_page ON chunks(page_id);

        CREATE VIRTUAL TABLE IF NOT EXISTS pages_fts USING fts5(
            title,
            summary,
            tokenize='porter unicode61'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            text,
            tokenize='porter unicode61'
        );
        """

        // Execute schema - split by semicolons for separate statements
        for statement in schema.components(separatedBy: ";") {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            try execute(trimmed)
        }

        // Create vector tables
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS pages_title_vec USING vec0(
                page_id INTEGER PRIMARY KEY,
                embedding float[\(embeddingDimension)]
            )
        """)

        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS pages_summary_vec USING vec0(
                page_id INTEGER PRIMARY KEY,
                embedding float[\(embeddingDimension)]
            )
        """)

        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(
                chunk_id INTEGER PRIMARY KEY,
                page_id INTEGER,
                embedding float[\(embeddingDimension)]
            )
        """)

        // FTS triggers - use INSERT OR REPLACE pattern for updates
        try execute("""
            CREATE TRIGGER IF NOT EXISTS pages_fts_insert AFTER INSERT ON pages BEGIN
                INSERT INTO pages_fts(rowid, title, summary) VALUES (new.id, new.title, new.summary);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS pages_fts_update AFTER UPDATE OF title, summary ON pages BEGIN
                DELETE FROM pages_fts WHERE rowid = old.id;
                INSERT INTO pages_fts(rowid, title, summary) VALUES (new.id, new.title, new.summary);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS pages_fts_delete AFTER DELETE ON pages BEGIN
                DELETE FROM pages_fts WHERE rowid = old.id;
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS chunks_fts_insert AFTER INSERT ON chunks BEGIN
                INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS chunks_fts_delete AFTER DELETE ON chunks BEGIN
                DELETE FROM chunks_fts WHERE rowid = old.id;
            END
        """)
    }

    // MARK: - Page Operations

    func upsertPage(url: URL, title: String?, workspaceID: UUID? = nil) throws -> Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        let domain = url.host ?? ""

        let sql = """
            INSERT INTO pages (url, title, domain, first_visited_at, last_visited_at, visit_count, workspace_id)
            VALUES (?, ?, ?, ?, ?, 1, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = COALESCE(excluded.title, title),
                last_visited_at = excluded.last_visited_at,
                visit_count = visit_count + 1
            RETURNING id
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, url.absoluteString, -1, SQLITE_TRANSIENT)
        if let title = title {
            sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, domain, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, now)
        sqlite3_bind_int64(stmt, 5, now)
        if let workspaceID = workspaceID {
            sqlite3_bind_text(stmt, 6, workspaceID.uuidString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_column_int64(stmt, 0)
    }

    func updatePageContent(pageId: Int64, title: String?, fullText: String) throws {
        let sql = """
            UPDATE pages
            SET title = COALESCE(?, title), full_text = ?, content_extracted = 1
            WHERE id = ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        if let title = title {
            sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, fullText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, pageId)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updatePageTitleEmbedding(pageId: Int64, embedding: [Float]) throws {
        print("SearchDatabase: updatePageTitleEmbedding - updating blob")
        // Update blob in pages table
        try updateEmbeddingBlob(
            sql: "UPDATE pages SET title_embedding = ? WHERE id = ?",
            id: pageId,
            embedding: embedding
        )

        print("SearchDatabase: updatePageTitleEmbedding - deleting old vec entry")
        // Delete existing vector entry first (vec0 doesn't support INSERT OR REPLACE)
        try execute("DELETE FROM pages_title_vec WHERE page_id = \(pageId)")

        print("SearchDatabase: updatePageTitleEmbedding - inserting vec entry (dim=\(embedding.count))")
        // Insert into vector table
        try insertVector(
            sql: "INSERT INTO pages_title_vec (page_id, embedding) VALUES (?, ?)",
            id: pageId,
            embedding: embedding
        )
        print("SearchDatabase: updatePageTitleEmbedding - done")
    }

    func updatePageSummary(pageId: Int64, summary: String, embedding: [Float]) throws {
        print("SearchDatabase: updatePageSummary - checking integrity first...")
        try verifyIntegrity()
        print("SearchDatabase: updatePageSummary - integrity OK, updating pages table")
        let sql = """
            UPDATE pages
            SET summary = ?, summary_embedding = ?, summary_generated = 1
            WHERE id = ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, summary, -1, SQLITE_TRANSIENT)
        _ = embedding.withUnsafeBytes { buffer in
            sqlite3_bind_blob(stmt, 2, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_int64(stmt, 3, pageId)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
        print("SearchDatabase: updatePageSummary - pages table updated")

        print("SearchDatabase: updatePageSummary - deleting old summary vec")
        // Delete existing vector entry first (vec0 doesn't support INSERT OR REPLACE)
        try execute("DELETE FROM pages_summary_vec WHERE page_id = \(pageId)")
        print("SearchDatabase: updatePageSummary - deleted, now inserting (dim=\(embedding.count))")

        // Insert into vector table
        try insertVector(
            sql: "INSERT INTO pages_summary_vec (page_id, embedding) VALUES (?, ?)",
            id: pageId,
            embedding: embedding
        )
        print("SearchDatabase: updatePageSummary - done")
    }

    func markEmbeddingsGenerated(pageId: Int64) throws {
        try execute("UPDATE pages SET embeddings_generated = 1 WHERE id = \(pageId)")
    }

    func getPage(id: Int64) throws -> PageRecord? {
        let sql = "SELECT * FROM pages WHERE id = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, id)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return pageFromStatement(stmt)
    }

    func getPendingPages(limit: Int = 50) throws -> [PageRecord] {
        let sql = """
            SELECT * FROM pages
            WHERE content_extracted = 1 AND embeddings_generated = 0
            ORDER BY last_visited_at DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var pages: [PageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let page = pageFromStatement(stmt) {
                pages.append(page)
            }
        }

        return pages
    }

    // MARK: - Chunk Operations

    func insertChunks(pageId: Int64, chunks: [String], embeddings: [[Float]]) throws {
        // Delete existing chunk vectors first (vec0 doesn't cascade)
        try execute("DELETE FROM chunks_vec WHERE page_id = \(pageId)")
        // Delete existing chunks for this page
        try execute("DELETE FROM chunks WHERE page_id = \(pageId)")

        let sql = "INSERT INTO chunks (page_id, chunk_index, text, embedding) VALUES (?, ?, ?, ?)"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        // Collect chunk IDs for vec0 inserts (done outside transaction)
        var chunkIds: [Int64] = []

        // Insert chunks into regular table (with transaction for performance)
        try execute("BEGIN TRANSACTION")
        do {
            for (index, (text, embedding)) in zip(chunks, embeddings).enumerated() {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_int64(stmt, 1, pageId)
                sqlite3_bind_int(stmt, 2, Int32(index))
                sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
                _ = embedding.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(stmt, 4, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
                }

                chunkIds.append(sqlite3_last_insert_rowid(db))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }

        // Insert into vec0 tables OUTSIDE the transaction
        for (chunkId, embedding) in zip(chunkIds, embeddings) {
            try insertChunkVector(chunkId: chunkId, pageId: pageId, embedding: embedding)
        }
    }

    func getChunks(pageId: Int64) throws -> [ChunkRecord] {
        let sql = "SELECT id, page_id, chunk_index, text FROM chunks WHERE page_id = ? ORDER BY chunk_index"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, pageId)

        var chunks: [ChunkRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunk = ChunkRecord(
                id: sqlite3_column_int64(stmt, 0),
                pageId: sqlite3_column_int64(stmt, 1),
                chunkIndex: Int(sqlite3_column_int(stmt, 2)),
                text: String(cString: sqlite3_column_text(stmt, 3))
            )
            chunks.append(chunk)
        }

        return chunks
    }

    // MARK: - Vector Search

    func vectorSearch(table: String, embedding: [Float], limit: Int) throws -> [(Int64, Double)] {
        let idColumn = table.contains("chunks") ? "chunk_id" : "page_id"
        // vec0 requires k = ? in WHERE clause for KNN queries
        // Results are automatically ordered by distance
        let sql = """
            SELECT \(idColumn), distance
            FROM \(table)
            WHERE embedding MATCH ? AND k = ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        SqliteVec.bindVector(stmt!, index: 1, vector: embedding)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [(Int64, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let distance = sqlite3_column_double(stmt, 1)
            let score = 1.0 / (1.0 + distance)
            results.append((id, score))
        }

        return results
    }

    func vectorSearchChunks(embedding: [Float], pageIds: [Int64], limit: Int) throws -> [(Int64, Double)] {
        guard !pageIds.isEmpty else { return [] }

        // vec0 requires k = ? for KNN queries
        // Can't filter by page_id in KNN query, so we fetch more and filter in code
        let kValue = limit * 20  // Fetch extra to account for filtering
        let sql = """
            SELECT page_id, distance
            FROM chunks_vec
            WHERE embedding MATCH ? AND k = ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        SqliteVec.bindVector(stmt!, index: 1, vector: embedding)
        sqlite3_bind_int(stmt, 2, Int32(kValue))

        // Collect results and filter by pageIds, keeping best distance per page
        let pageIdSet = Set(pageIds)
        var bestByPage: [Int64: Double] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let pageId = sqlite3_column_int64(stmt, 0)
            let distance = sqlite3_column_double(stmt, 1)

            // Only include if in requested pageIds
            guard pageIdSet.contains(pageId) else { continue }

            // Keep best (lowest) distance per page
            if let existing = bestByPage[pageId] {
                if distance < existing {
                    bestByPage[pageId] = distance
                }
            } else {
                bestByPage[pageId] = distance
            }
        }

        // Convert to results sorted by distance, limited
        return bestByPage
            .map { (pageId, distance) in (pageId, 1.0 / (1.0 + distance)) }
            .sorted { $0.1 > $1.1 }  // Sort by score descending
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - FTS Search

    func ftsSearch(table: String, query: String, limit: Int) throws -> [(Int64, Double)] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        let sql = """
            SELECT rowid, bm25(\(table)) as score
            FROM \(table)
            WHERE \(table) MATCH ?
            ORDER BY score
            LIMIT ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, sanitized, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [(Int64, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let score = -sqlite3_column_double(stmt, 1)  // BM25 returns negative
            results.append((id, score))
        }

        return results
    }

    func ftsSearchChunks(query: String, limit: Int) throws -> [(Int64, Double)] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        let sql = """
            SELECT c.page_id, MIN(bm25(chunks_fts)) as best_score
            FROM chunks_fts
            JOIN chunks c ON c.id = chunks_fts.rowid
            WHERE chunks_fts MATCH ?
            GROUP BY c.page_id
            ORDER BY best_score
            LIMIT ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, sanitized, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [(Int64, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pageId = sqlite3_column_int64(stmt, 0)
            let score = -sqlite3_column_double(stmt, 1)
            results.append((pageId, score))
        }

        return results
    }

    // MARK: - Stats

    func getStats() throws -> SearchStats {
        SearchStats(
            pageCount: try queryInt("SELECT COUNT(*) FROM pages"),
            chunkCount: try queryInt("SELECT COUNT(*) FROM chunks"),
            pendingCount: try queryInt("SELECT COUNT(*) FROM pages WHERE content_extracted = 1 AND embeddings_generated = 0"),
            indexedCount: try queryInt("SELECT COUNT(*) FROM pages WHERE embeddings_generated = 1")
        )
    }

    // MARK: - Maintenance

    func deleteOldPages(olderThanDays: Int) throws -> Int {
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(olderThanDays * 86400)

        let countSql = "SELECT COUNT(*) FROM pages WHERE last_visited_at < ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, countSql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, cutoff)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        let count = Int(sqlite3_column_int(stmt, 0))

        try execute("DELETE FROM pages WHERE last_visited_at < \(cutoff)")
        return count
    }

    func vacuum() throws {
        try execute("VACUUM")
    }

    // MARK: - Private Helpers

    private func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if result != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            print("SearchDatabase: execute failed (\(result)) for: \(sql.prefix(80))... - \(error)")
            throw SearchDBError.executeFailed(error)
        }
    }

    private func queryInt(_ sql: String) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func updateEmbeddingBlob(sql: String, id: Int64, embedding: [Float]) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        SqliteVec.bindVector(stmt!, index: 1, vector: embedding)
        sqlite3_bind_int64(stmt, 2, id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func insertVector(sql: String, id: Int64, embedding: [Float]) throws {
        print("SearchDatabase: insertVector - sql=\(sql.prefix(60))..., id=\(id), dim=\(embedding.count)")
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            print("SearchDatabase: insertVector - prepare failed: \(err)")
            throw SearchDBError.prepareFailed(err)
        }

        sqlite3_bind_int64(stmt, 1, id)
        SqliteVec.bindVector(stmt!, index: 2, vector: embedding)

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_DONE else {
            let err = String(cString: sqlite3_errmsg(db))
            print("SearchDatabase: insertVector - step failed (\(stepResult)): \(err)")
            throw SearchDBError.executeFailed(err)
        }
        print("SearchDatabase: insertVector - done")
    }

    private func insertChunkVector(chunkId: Int64, pageId: Int64, embedding: [Float]) throws {
        let sql = "INSERT INTO chunks_vec (chunk_id, page_id, embedding) VALUES (?, ?, ?)"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, chunkId)
        sqlite3_bind_int64(stmt, 2, pageId)
        SqliteVec.bindVector(stmt!, index: 3, vector: embedding)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func pageFromStatement(_ stmt: OpaquePointer?) -> PageRecord? {
        guard let stmt = stmt else { return nil }

        guard let urlString = sqlite3_column_text(stmt, 1),
              let url = URL(string: String(cString: urlString)) else {
            return nil
        }

        return PageRecord(
            id: sqlite3_column_int64(stmt, 0),
            url: url,
            title: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
            domain: String(cString: sqlite3_column_text(stmt, 3)),
            fullText: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
            summary: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
            firstVisitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 8))),
            lastVisitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 9))),
            visitCount: Int(sqlite3_column_int(stmt, 10)),
            workspaceID: sqlite3_column_text(stmt, 11).flatMap { UUID(uuidString: String(cString: $0)) },
            contentExtracted: sqlite3_column_int(stmt, 12) != 0,
            summaryGenerated: sqlite3_column_int(stmt, 13) != 0,
            embeddingsGenerated: sqlite3_column_int(stmt, 14) != 0
        )
    }

    private func sanitizeFTSQuery(_ query: String) -> String {
        let terms = query
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { term -> String in
                term.replacingOccurrences(
                    of: "[\"'\\-\\+\\*\\(\\)\\{\\}\\[\\]\\^\\~\\:\\@\\#\\$\\%\\&]",
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { !$0.isEmpty }

        return terms.joined(separator: " OR ")
    }
}

// MARK: - Types

struct PageRecord: Identifiable {
    let id: Int64
    let url: URL
    let title: String?
    let domain: String
    let fullText: String?
    let summary: String?
    let firstVisitedAt: Date
    let lastVisitedAt: Date
    let visitCount: Int
    let workspaceID: UUID?
    let contentExtracted: Bool
    let summaryGenerated: Bool
    let embeddingsGenerated: Bool

    var snippet: String {
        let text = summary ?? fullText ?? title ?? ""
        return String(text.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChunkRecord: Identifiable {
    let id: Int64
    let pageId: Int64
    let chunkIndex: Int
    let text: String
}

struct SearchStats {
    let pageCount: Int
    let chunkCount: Int
    let pendingCount: Int
    let indexedCount: Int
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

// SQLITE_TRANSIENT helper
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
