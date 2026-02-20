import Foundation
import SwiftUI

/// Manages semantic search using sqlite-vec and configurable embedding services
@MainActor
class SemanticSearchManagerV2: ObservableObject {
    static let shared = SemanticSearchManagerV2()

    @Published private(set) var isIndexing = false
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isAvailable = false

    private var db: SearchDatabase?
    private var embeddingService: (any EmbeddingService)?
    private var searchEngine: SearchEngine?
    private var indexingPipeline: IndexingPipeline?

    private var settings: AppSettings { AppSettings.shared }
    private var settingsObserver: NSObjectProtocol?
    private var dimensionsObserver: NSObjectProtocol?

    /// Prevents concurrent initialization/reinitialization
    private var isReinitializing = false
    /// Skip the next settings change notification (used when dimensions change triggers both notifications)
    private var skipNextSettingsChange = false

    private init() {
        // Listen for settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .embeddingSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Skip if this was triggered by a dimension change (which handles its own reinitialization)
                if self.skipNextSettingsChange {
                    self.skipNextSettingsChange = false
                    return
                }
                await self.reinitialize()
            }
        }

        // Listen for dimension changes - requires clearing the index
        dimensionsObserver = NotificationCenter.default.addObserver(
            forName: .embeddingDimensionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Mark to skip the settings change notification that follows dimension changes
                self.skipNextSettingsChange = true
                print("Embedding dimensions changed - clearing index")
                await self.clearAndReinitialize()
            }
        }

        Task {
            await initialize()
        }
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = dimensionsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        print("SemanticSearchManagerV2: initialize() called, enabled=\(settings.semanticSearchEnabled)")
        guard settings.semanticSearchEnabled else {
            isAvailable = false
            return
        }

        do {
            // Initialize database with configured dimensions
            let dimensions = settings.embeddingDimensions
            print("SemanticSearchManagerV2: Creating SearchDatabase with dimensions=\(dimensions)")
            let database = try SearchDatabase(embeddingDimension: dimensions)
            try await database.initialize()
            db = database
            print("SemanticSearchManagerV2: Database initialized successfully")

            // Create embedding service based on settings
            embeddingService = settings.makeEmbeddingService()

            // Initialize search engine and indexing pipeline
            if let db = db, let embeddingService = embeddingService {
                searchEngine = SearchEngine(db: db, embeddingService: embeddingService)
                indexingPipeline = IndexingPipeline(db: db, embeddingService: embeddingService)
                isAvailable = true

                // Update stats
                await updateStats()

                // Process any pending pages from previous sessions
                await indexingPipeline?.processPendingPages()
            }
        } catch {
            lastError = error.localizedDescription
            isAvailable = false
            print("Failed to initialize SemanticSearchManagerV2: \(error)")
        }
    }

    /// Reinitialize with new settings (call after changing embedding provider)
    func reinitialize() async {
        // Prevent concurrent reinitializations
        guard !isReinitializing else {
            print("SemanticSearchManagerV2: Skipping reinitialize, already in progress")
            return
        }
        isReinitializing = true
        defer { isReinitializing = false }

        // Close existing database connection first
        await closeDatabase()

        embeddingService = nil
        searchEngine = nil
        indexingPipeline = nil
        isAvailable = false
        lastError = nil

        await initialize()
    }

    /// Close the database connection properly
    private func closeDatabase() async {
        if let db = db {
            // Give the actor a chance to clean up
            await db.close()
        }
        db = nil
    }

    // MARK: - Indexing

    /// Index a page for semantic search
    func indexPage(url: String, title: String, content: String, workspaceID: UUID? = nil) async {
        guard isAvailable, let indexingPipeline = indexingPipeline else { return }
        guard let pageURL = URL(string: url) else { return }

        isIndexing = true
        defer { isIndexing = false }

        do {
            try await indexingPipeline.indexPage(
                url: pageURL,
                title: title,
                content: content,
                workspaceID: workspaceID
            )
            await updateStats()
        } catch {
            lastError = error.localizedDescription
            print("Indexing error: \(error)")
        }
    }

    /// Register a page without content extraction (for PDFs and other non-indexable content)
    /// This creates a minimal database record so the page can be saved to reading list
    func registerPage(url: String, title: String, workspaceID: UUID? = nil) async {
        guard isAvailable, let db = db else { return }
        guard let pageURL = URL(string: url) else { return }

        do {
            _ = try await db.upsertPage(url: pageURL, title: title, workspaceID: workspaceID)
        } catch {
            print("Failed to register page: \(error)")
        }
    }

    // MARK: - Search

    /// Search for pages semantically similar to the query
    func search(query: String, limit: Int = 20) async -> [SemanticSearchResult] {
        guard isAvailable, let searchEngine = searchEngine else { return [] }

        do {
            let results = try await searchEngine.search(query: query)
            return results.prefix(limit).map { result in
                SemanticSearchResult(
                    id: result.id,
                    page: IndexedPage(
                        id: result.id,
                        url: result.page.url.absoluteString,
                        title: result.page.title ?? "",
                        snippet: result.snippet,
                        timestamp: result.page.lastVisitedAt,
                        workspaceID: result.page.workspaceID
                    ),
                    score: result.score
                )
            }
        } catch {
            lastError = error.localizedDescription
            print("Search error: \(error)")
            return []
        }
    }

    /// Quick keyword search (FTS only, no embeddings)
    func quickSearch(query: String, limit: Int = 10) async -> [SemanticSearchResult] {
        guard isAvailable, let searchEngine = searchEngine else { return [] }

        do {
            let results = try await searchEngine.quickSearch(query: query, limit: limit)
            return results.map { result in
                SemanticSearchResult(
                    id: result.id,
                    page: IndexedPage(
                        id: result.id,
                        url: result.page.url.absoluteString,
                        title: result.page.title ?? "",
                        snippet: result.snippet,
                        timestamp: result.page.lastVisitedAt,
                        workspaceID: result.page.workspaceID
                    ),
                    score: result.score
                )
            }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Stats

    var stats: (count: Int, available: Bool) {
        (indexedCount, isAvailable)
    }

    private func updateStats() async {
        guard let db = db else { return }

        do {
            let stats = try await db.getStats()
            indexedCount = stats.indexedCount
            pendingCount = stats.pendingCount
        } catch {
            print("Failed to get stats: \(error)")
        }
    }

    // MARK: - Maintenance

    /// Clear the entire index and reinitialize (used when dimensions change)
    func clearAndReinitialize() async {
        // Prevent concurrent reinitializations
        guard !isReinitializing else {
            print("SemanticSearchManagerV2: Skipping clearAndReinitialize, already in progress")
            return
        }
        isReinitializing = true
        defer { isReinitializing = false }

        // Close existing database connection properly before deleting
        await closeDatabase()

        embeddingService = nil
        searchEngine = nil
        indexingPipeline = nil
        isAvailable = false

        // Delete the database file
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("WheelBrowser")

        let dbPath = appSupport.appendingPathComponent("semantic_search.db")
        let walPath = appSupport.appendingPathComponent("semantic_search.db-wal")
        let shmPath = appSupport.appendingPathComponent("semantic_search.db-shm")

        // Small delay to ensure database file handles are released
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Remove database and WAL files
        try? FileManager.default.removeItem(at: dbPath)
        try? FileManager.default.removeItem(at: walPath)
        try? FileManager.default.removeItem(at: shmPath)

        indexedCount = 0
        pendingCount = 0

        // Reinitialize with new settings
        await initialize()
    }

    /// Clear the entire index
    func clearIndex() async {
        await clearAndReinitialize()
    }

    /// Save/sync the index (called on app termination)
    func save() async {
        // SQLite with WAL handles this automatically
        // This is here for API compatibility with the old manager
    }
}

// MARK: - Bridge for existing code

extension SemanticSearchManagerV2 {
    /// For compatibility with existing SemanticSearchManager API
    @MainActor
    static var current: SemanticSearchManagerV2 {
        shared
    }
}
