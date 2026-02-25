import Foundation
import SQLite3

/// SQLite-based database for reading list and page metadata
actor SearchDatabase {
    private var db: OpaquePointer?
    private let dbPath: URL
    private var isInitialized = false

    init() throws {
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
        try openDatabase()
        try verifyIntegrity()
        try createSchema()
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

        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
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
            first_visited_at INTEGER NOT NULL,
            last_visited_at INTEGER NOT NULL,
            visit_count INTEGER DEFAULT 1,
            workspace_id TEXT,
            is_saved INTEGER DEFAULT 0,
            saved_at INTEGER
        );

        CREATE INDEX IF NOT EXISTS idx_pages_domain ON pages(domain);
        CREATE INDEX IF NOT EXISTS idx_pages_last_visited ON pages(last_visited_at DESC);
        CREATE INDEX IF NOT EXISTS idx_pages_workspace ON pages(workspace_id);

        CREATE VIRTUAL TABLE IF NOT EXISTS pages_fts USING fts5(
            title,
            summary,
            tokenize='porter unicode61'
        );
        """

        for statement in schema.components(separatedBy: ";") {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            try execute(trimmed)
        }

        // FTS triggers
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

        try runMigrations()
        try execute("CREATE INDEX IF NOT EXISTS idx_pages_saved ON pages(is_saved, saved_at DESC) WHERE is_saved = 1")
    }

    private func runMigrations() throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "PRAGMA table_info(pages)", -1, &stmt, nil) == SQLITE_OK else {
            return
        }

        var hasIsSaved = false
        var hasSavedAt = false

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 1) {
                let name = String(cString: namePtr)
                if name == "is_saved" { hasIsSaved = true }
                if name == "saved_at" { hasSavedAt = true }
            }
        }

        if !hasIsSaved {
            try execute("ALTER TABLE pages ADD COLUMN is_saved INTEGER DEFAULT 0")
        }
        if !hasSavedAt {
            try execute("ALTER TABLE pages ADD COLUMN saved_at INTEGER")
        }
    }

    // MARK: - Page Operations

    /// Insert or update a page, returning its ID
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

    // MARK: - Reading List Operations

    /// Toggle the saved state of a page by URL. Creates the page if it doesn't exist.
    func toggleSaved(url: String, title: String? = nil) throws -> Bool {
        guard let pageURL = URL(string: url) else {
            return false
        }

        // First check if page exists
        let checkSql = "SELECT id, is_saved FROM pages WHERE url = ?"
        var checkStmt: OpaquePointer?
        defer { sqlite3_finalize(checkStmt) }

        guard sqlite3_prepare_v2(db, checkSql, -1, &checkStmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(checkStmt, 1, url, -1, SQLITE_TRANSIENT)

        if sqlite3_step(checkStmt) == SQLITE_ROW {
            // Page exists, toggle its state
            let currentState = sqlite3_column_int(checkStmt, 1) != 0
            let newState = !currentState
            try setSaved(url: url, saved: newState)
            return newState
        } else {
            // Page doesn't exist - create it and mark as saved
            _ = try upsertPage(url: pageURL, title: title)
            try setSaved(url: url, saved: true)
            return true
        }
    }

    /// Set the saved state of a page
    func setSaved(url: String, saved: Bool) throws {
        let now = saved ? Int64(Date().timeIntervalSince1970) : 0
        let sql = "UPDATE pages SET is_saved = ?, saved_at = ? WHERE url = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, saved ? 1 : 0)
        if saved {
            sqlite3_bind_int64(stmt, 2, now)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Check if a URL is saved
    func isSaved(url: String) throws -> Bool {
        let sql = "SELECT is_saved FROM pages WHERE url = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return false
        }

        return sqlite3_column_int(stmt, 0) != 0
    }

    /// Get all saved pages ordered by save date
    func getSavedPages(limit: Int = 100) throws -> [SavedPageRecord] {
        let sql = """
            SELECT id, url, title, domain, summary, saved_at, last_visited_at
            FROM pages
            WHERE is_saved = 1
            ORDER BY saved_at DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var pages: [SavedPageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlString = sqlite3_column_text(stmt, 1),
                  let url = URL(string: String(cString: urlString)) else {
                continue
            }

            let page = SavedPageRecord(
                id: sqlite3_column_int64(stmt, 0),
                url: url,
                title: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                domain: String(cString: sqlite3_column_text(stmt, 3)),
                summary: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                savedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 5))),
                lastVisitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 6)))
            )
            pages.append(page)
        }

        return pages
    }

    /// Search saved pages using FTS
    func searchSavedPages(query: String, limit: Int = 50) throws -> [SavedPageRecord] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else {
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

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, sanitized, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var pages: [SavedPageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlString = sqlite3_column_text(stmt, 1),
                  let url = URL(string: String(cString: urlString)) else {
                continue
            }

            let page = SavedPageRecord(
                id: sqlite3_column_int64(stmt, 0),
                url: url,
                title: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                domain: String(cString: sqlite3_column_text(stmt, 3)),
                summary: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                savedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 5))),
                lastVisitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 6)))
            )
            pages.append(page)
        }

        return pages
    }

    // MARK: - Summary Operations

    /// Update the summary for a page by URL
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

    /// Clear all summaries for saved pages (used before regeneration)
    func clearAllSummaries() throws {
        let sql = "UPDATE pages SET summary = NULL WHERE is_saved = 1"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Get saved pages that don't have a summary yet
    func getSavedPagesWithoutSummary(limit: Int = 20) throws -> [SavedPageRecord] {
        let sql = """
            SELECT id, url, title, domain, summary, saved_at, last_visited_at
            FROM pages
            WHERE is_saved = 1 AND (summary IS NULL OR summary = '')
            ORDER BY saved_at DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var pages: [SavedPageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlString = sqlite3_column_text(stmt, 1),
                  let url = URL(string: String(cString: urlString)) else {
                continue
            }

            let page = SavedPageRecord(
                id: sqlite3_column_int64(stmt, 0),
                url: url,
                title: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                domain: String(cString: sqlite3_column_text(stmt, 3)),
                summary: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                savedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 5))),
                lastVisitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 6)))
            )
            pages.append(page)
        }

        return pages
    }

    // MARK: - Maintenance

    func vacuum() throws {
        try execute("VACUUM")
    }

    /// Clear all reading list items (unsave all saved pages)
    func clearReadingList() throws {
        try execute("UPDATE pages SET is_saved = 0, saved_at = NULL WHERE is_saved = 1")
    }

    /// Delete all data from the database
    func clearAllData() throws {
        try execute("DELETE FROM pages_fts")
        try execute("DELETE FROM pages")
    }

    // MARK: - Private Helpers

    private func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if result != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            throw SearchDBError.executeFailed(error)
        }
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

struct SavedPageRecord: Identifiable {
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
