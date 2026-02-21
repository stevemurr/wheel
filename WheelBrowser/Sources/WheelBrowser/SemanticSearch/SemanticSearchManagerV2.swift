import Foundation
import SwiftUI

/// Manages semantic search using remote DIndex server
@MainActor
class SemanticSearchManagerV2: ObservableObject {
    static let shared = SemanticSearchManagerV2()

    @Published private(set) var isIndexing = false
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isAvailable = false
    @Published private(set) var isDIndexConnected = false

    private var dindexService: DIndexService?

    private var settings: AppSettings { AppSettings.shared }
    private var settingsObserver: NSObjectProtocol?

    private init() {
        // Listen for settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .embeddingSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                await self.reinitialize()
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
    }

    // MARK: - Initialization

    private func initialize() async {
        guard settings.dindexEnabled else {
            isAvailable = false
            isDIndexConnected = false
            return
        }

        await initializeDIndex()
    }

    /// Initialize remote DIndex service
    private func initializeDIndex() async {
        guard settings.dindexEnabled,
              let endpoint = URL(string: settings.dindexEndpoint) else {
            dindexService = nil
            isDIndexConnected = false
            isAvailable = false
            return
        }

        let apiKey = settings.dindexAPIKey.isEmpty ? nil : settings.dindexAPIKey
        let service = DIndexService(endpoint: endpoint, apiKey: apiKey)

        // Verify connection
        let healthy = await service.checkHealth()
        if healthy {
            dindexService = service
            isDIndexConnected = true
            isAvailable = true
            lastError = nil
            print("SemanticSearchManagerV2: DIndex connected at \(settings.dindexEndpoint)")

            // Fetch initial stats
            await updateStats()
        } else {
            dindexService = nil
            isDIndexConnected = false
            isAvailable = false
            lastError = "Could not connect to DIndex server"
            print("SemanticSearchManagerV2: DIndex health check failed")
        }
    }

    /// Reinitialize with new settings
    func reinitialize() async {
        dindexService = nil
        isDIndexConnected = false
        isAvailable = false
        lastError = nil

        await initialize()
    }

    // MARK: - Indexing

    /// Index a page for semantic search
    func indexPage(
        url: String,
        title: String,
        content: String,
        workspaceID: UUID? = nil,
        categories: Set<EmbeddingCategory> = [.history, .web]
    ) async {
        guard isAvailable, let dindex = dindexService else { return }
        guard let pageURL = URL(string: url) else { return }

        isIndexing = true
        defer { isIndexing = false }

        do {
            try await dindex.indexPage(
                url: pageURL,
                title: title,
                content: content,
                categories: categories
            )
            await updateStats()
        } catch {
            lastError = error.localizedDescription
            print("Indexing error: \(error)")
        }
    }

    /// Register a page without content extraction (for PDFs and other non-indexable content)
    func registerPage(url: String, title: String, workspaceID: UUID? = nil) async {
        // No-op for DIndex-only mode - pages are indexed with content
    }

    // MARK: - Search

    /// Search for pages semantically similar to the query
    func search(query: String, limit: Int = 20) async -> [SemanticSearchResult] {
        guard isAvailable, let dindex = dindexService else { return [] }

        do {
            let results = try await dindex.search(query: query, limit: limit)
            return results.map { item in
                let hashValue = item.id.hashValue
                let id = UInt64(bitPattern: Int64(hashValue))
                return SemanticSearchResult(
                    id: id,
                    page: IndexedPage(
                        id: id,
                        url: item.url ?? "",
                        title: item.title ?? "",
                        snippet: String(item.content.prefix(200)),
                        timestamp: Date(),
                        workspaceID: nil
                    ),
                    score: item.score
                )
            }
        } catch {
            lastError = error.localizedDescription
            print("Search error: \(error)")
            return []
        }
    }

    /// Search with category filtering
    func searchWithCategories(
        query: String,
        categories: Set<EmbeddingCategory>,
        limit: Int = 20
    ) async -> [SemanticSearchResult] {
        guard isAvailable, let dindex = dindexService else { return [] }

        do {
            let results = try await dindex.search(
                query: query,
                categories: categories.isEmpty ? nil : categories,
                limit: limit
            )
            return results.map { item in
                let hashValue = item.id.hashValue
                let id = UInt64(bitPattern: Int64(hashValue))
                return SemanticSearchResult(
                    id: id,
                    page: IndexedPage(
                        id: id,
                        url: item.url ?? "",
                        title: item.title ?? "",
                        snippet: String(item.content.prefix(200)),
                        timestamp: Date(),
                        workspaceID: nil
                    ),
                    score: item.score
                )
            }
        } catch {
            lastError = error.localizedDescription
            print("DIndex search error: \(error)")
            return []
        }
    }

    // MARK: - Stats

    var stats: (count: Int, available: Bool) {
        (indexedCount, isAvailable)
    }

    private func updateStats() async {
        guard let dindex = dindexService else {
            indexedCount = 0
            return
        }

        do {
            let stats = try await dindex.getStats()
            indexedCount = stats.totalChunks
        } catch {
            print("Failed to get DIndex stats: \(error)")
        }
    }

    // MARK: - Maintenance

    /// Clear the index - not supported in DIndex mode
    func clearIndex() async {
        // No-op - DIndex manages its own storage
    }

    /// Save/sync the index (called on app termination)
    func save() async {
        // No-op - DIndex handles persistence
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

// MARK: - Result Types

/// A semantic search result
struct SemanticSearchResult: Identifiable {
    let id: UInt64
    let page: IndexedPage
    let score: Float
}

/// An indexed page
struct IndexedPage: Identifiable {
    let id: UInt64
    let url: String
    let title: String
    let snippet: String
    let timestamp: Date
    let workspaceID: UUID?
}
