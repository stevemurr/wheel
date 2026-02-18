import Foundation
import NaturalLanguage
import USearch

/// Represents a page stored in the semantic index
struct IndexedPage: Codable, Identifiable {
    let id: UInt64
    let url: String
    let title: String
    let snippet: String
    let timestamp: Date
    let workspaceID: UUID?
}

/// Result from a semantic search
struct SemanticSearchResult: Identifiable {
    let id: UInt64
    let page: IndexedPage
    let score: Float
}

/// Manages semantic search over browsing history using vector embeddings
@MainActor
class SemanticSearchManager: ObservableObject {
    static let shared = SemanticSearchManager()

    @Published private(set) var isIndexing = false
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var lastError: String?

    private var index: USearchIndex?
    private var pages: [UInt64: IndexedPage] = [:]
    private var nextId: UInt64 = 1
    private var reservedCapacity: UInt32 = 0

    private let embedding: NLEmbedding?
    private let dimensions: UInt32 = 512 // NLEmbedding sentence embedding dimension

    private var indexPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("semantic.usearch")
    }

    private var pagesPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)
        return appDir.appendingPathComponent("semantic_pages.json")
    }

    private init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)

        if embedding == nil {
            lastError = "Sentence embeddings not available"
            print("Warning: NLEmbedding.sentenceEmbedding not available on this system")
        }

        Task {
            await loadIndex()
        }
    }

    // MARK: - Index Management

    private func loadIndex() async {
        // Load page metadata
        if FileManager.default.fileExists(atPath: pagesPath.path) {
            do {
                let data = try Data(contentsOf: pagesPath)
                let decoded = try JSONDecoder().decode([UInt64: IndexedPage].self, from: data)
                pages = decoded
                nextId = (pages.keys.max() ?? 0) + 1
                indexedCount = pages.count
            } catch {
                print("Failed to load semantic pages: \(error)")
                lastError = "Failed to load index metadata"
            }
        }

        // Create or load USearch index
        do {
            index = try USearchIndex.make(
                metric: .cos,
                dimensions: dimensions,
                connectivity: 16,
                quantization: .f32
            )

            if FileManager.default.fileExists(atPath: indexPath.path) {
                try index?.load(path: indexPath.path)
                // Loaded index should have capacity already
                reservedCapacity = UInt32(((pages.count / 1000) + 1) * 1000)
            } else {
                // Reserve initial capacity for new index
                try index?.reserve(1000)
                reservedCapacity = 1000
            }
        } catch {
            print("Failed to load USearch index: \(error)")
            lastError = "Failed to load vector index"
        }
    }

    private func saveIndex() async {
        // Save page metadata
        do {
            let data = try JSONEncoder().encode(pages)
            try data.write(to: pagesPath, options: .atomic)
        } catch {
            print("Failed to save semantic pages: \(error)")
        }

        // Save USearch index
        do {
            try index?.save(path: indexPath.path)
        } catch {
            print("Failed to save USearch index: \(error)")
        }
    }

    // MARK: - Embedding Generation

    private func generateEmbedding(for text: String) -> [Float]? {
        guard let embedding = embedding else { return nil }

        // Truncate to reasonable length for embedding
        let truncated = String(text.prefix(5000))

        guard let vector = embedding.vector(for: truncated) else { return nil }

        // Convert Double to Float
        return vector.map { Float($0) }
    }

    // MARK: - Indexing

    /// Index a page for semantic search
    func indexPage(url: String, title: String, content: String, workspaceID: UUID? = nil) async {
        guard let embeddingVector = generateEmbedding(for: "\(title) \(content)") else {
            return
        }

        isIndexing = true
        defer { isIndexing = false }

        // Check if URL already exists (update if so)
        if let existingId = pages.first(where: { $0.value.url == url })?.key {
            // Remove old entry from both pages dictionary and vector index
            pages.removeValue(forKey: existingId)
            do {
                _ = try index?.remove(key: existingId)
            } catch {
                print("Failed to remove old entry from index: \(error)")
            }
        }

        let pageId = nextId
        nextId += 1

        // Create snippet from content
        let snippet = String(content.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)

        let page = IndexedPage(
            id: pageId,
            url: url,
            title: title,
            snippet: snippet,
            timestamp: Date(),
            workspaceID: workspaceID
        )

        pages[pageId] = page
        indexedCount = pages.count

        // Add to vector index
        do {
            // Ensure capacity before adding (reserve in chunks of 1000)
            let neededCapacity = UInt32(((pages.count / 1000) + 1) * 1000)
            if neededCapacity > reservedCapacity {
                try index?.reserve(neededCapacity)
                reservedCapacity = neededCapacity
            }

            try embeddingVector.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                try index?.addSingle(key: pageId, vector: baseAddress)
            }
        } catch {
            print("Failed to add to index: \(error)")
        }

        // Save after each page is indexed
        await saveIndex()
    }

    /// Force save the index
    func save() async {
        await saveIndex()
    }

    // MARK: - Search

    /// Search for pages semantically similar to the query
    func search(query: String, limit: Int = 20) async -> [SemanticSearchResult] {
        guard let queryVector = generateEmbedding(for: query) else {
            return []
        }

        guard let index = index else { return [] }

        do {
            // Allocate output buffers
            var keys = [USearchKey](repeating: 0, count: limit)
            var distances = [Float32](repeating: 0, count: limit)

            let found = try queryVector.withUnsafeBufferPointer { vectorBuffer -> UInt32 in
                guard let vectorPtr = vectorBuffer.baseAddress else { return 0 }
                return try keys.withUnsafeMutableBufferPointer { keysBuffer in
                    return try distances.withUnsafeMutableBufferPointer { distancesBuffer in
                        return try index.searchSingle(
                            vector: vectorPtr,
                            count: UInt32(limit),
                            keys: keysBuffer.baseAddress,
                            distances: distancesBuffer.baseAddress
                        )
                    }
                }
            }

            return (0..<Int(found)).compactMap { i in
                let key = keys[i]
                let distance = distances[i]
                guard let page = pages[key] else { return nil }
                return SemanticSearchResult(
                    id: key,
                    page: page,
                    score: 1.0 - distance // Convert distance to similarity
                )
            }
        } catch {
            print("Search error: \(error)")
            return []
        }
    }

    /// Get statistics about the index
    var stats: (count: Int, available: Bool) {
        return (indexedCount, embedding != nil)
    }

    /// Clear the entire index
    func clearIndex() async {
        pages.removeAll()
        nextId = 1
        indexedCount = 0

        // Recreate empty index
        do {
            let newIndex = try USearchIndex.make(
                metric: .cos,
                dimensions: dimensions,
                connectivity: 16,
                quantization: .f32
            )
            try newIndex.reserve(1000)
            index = newIndex
            reservedCapacity = 1000
        } catch {
            print("Failed to recreate index: \(error)")
        }

        // Delete files
        try? FileManager.default.removeItem(at: indexPath)
        try? FileManager.default.removeItem(at: pagesPath)
    }
}
