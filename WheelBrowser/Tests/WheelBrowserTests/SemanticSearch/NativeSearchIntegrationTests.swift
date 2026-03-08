import Testing
import Foundation
import VecturaKit
@testable import WheelBrowser

// MARK: - Mock Embedder

/// Deterministic embedder for tests.
/// Maps known topics to specific unit vectors so cosine similarity is predictable.
actor MockVecturaEmbedder: VecturaEmbedder {
    private let dim = 64

    var dimension: Int {
        get async throws { dim }
    }

    private let topicAxes: [String: Int] = [
        "swift": 0,
        "programming": 0,
        "language": 0,
        "code": 0,
        "cooking": 1,
        "recipes": 1,
        "food": 1,
        "kitchen": 1,
        "astronomy": 2,
        "stars": 2,
        "planets": 2,
        "space": 2,
    ]

    func embed(text: String) async throws -> [Float] {
        makeVector(for: text)
    }

    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { makeVector(for: $0) }
    }

    private func makeVector(for text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dim)
        let words = text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }

        for word in words {
            if let axis = topicAxes[word] {
                vector[axis] += 1.0
            }
        }

        // If no topic matched, use a deterministic hash-based direction
        let hasNonZero = vector.contains { $0 != 0 }
        if !hasNonZero {
            let hash = abs(text.hashValue)
            let axis = hash % dim
            vector[axis] = 1.0
        }

        // L2 normalize
        var norm: Float = 0
        for v in vector { norm += v * v }
        norm = sqrt(norm)
        if norm > 1e-9 {
            for i in 0..<dim { vector[i] /= norm }
        }

        return vector
    }
}

// MARK: - Integration Tests

@Suite("Native Search Integration")
struct NativeSearchIntegrationTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeService(tempDir: URL) -> NativeSearchService {
        let dbPath = tempDir.appendingPathComponent("meta.db")
        return NativeSearchService(dbPath: dbPath, embedder: MockVecturaEmbedder())
    }

    private func cleanup(_ path: URL) {
        try? FileManager.default.removeItem(at: path)
    }

    private func makeLongTopicDocument(topic: String, uniqueToken: String, paragraphs: Int = 60) -> String {
        let sentence = """
        \(topic) \(uniqueToken) explains production app development, code organization, and language design patterns in detail.
        """
        let paragraph = Array(repeating: sentence, count: 16).joined(separator: " ")
        let body = (0..<paragraphs)
            .map { index in "\(paragraph) Section \(index) \(uniqueToken)." }
            .joined(separator: "\n\n")

        return """
        # \(uniqueToken.capitalized) Guide

        \(body)
        """
    }

    // MARK: - Tests

    @Test("Index a page and verify stats")
    func indexAndRetrieveDocument() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/swift")!,
            title: "Swift Programming",
            content: "Swift is a powerful programming language for iOS and macOS development. It provides modern syntax and safety features that make code easier to write and maintain.",
            categories: [.web]
        )

        let stats = try await service.getStats()
        #expect(stats.pageCount == 1)
        #expect(stats.chunkCount > 0)
    }

    @Test("Search returns relevant results ranked correctly")
    func searchReturnsRelevantResults() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        // Index three documents on different topics
        try await service.indexPage(
            url: URL(string: "https://example.com/swift")!,
            title: "Swift Programming",
            content: "Swift is a programming language for code development. Swift programming enables building apps with modern code patterns.",
            categories: [.web]
        )
        try await service.indexPage(
            url: URL(string: "https://example.com/cooking")!,
            title: "Cooking Recipes",
            content: "Cooking recipes for the kitchen. Food preparation and cooking techniques for delicious recipes.",
            categories: [.web]
        )
        try await service.indexPage(
            url: URL(string: "https://example.com/space")!,
            title: "Astronomy Guide",
            content: "Astronomy is the study of stars and planets in space. Stars and planets form the cosmos.",
            categories: [.web]
        )

        // Search for programming — should rank swift doc first
        let results = try await service.search(query: "swift programming code")
        #expect(!results.isEmpty)
        #expect(results[0].url == "https://example.com/swift")
    }

    @Test("Deduplication skips unchanged content")
    func deduplicationSkipsUnchangedContent() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        let content = "Swift is a programming language for code development. It has many features."

        try await service.indexPage(
            url: URL(string: "https://example.com/swift")!,
            title: "Swift",
            content: content,
            categories: [.web]
        )

        let stats1 = try await service.getStats()

        // Index same URL with same content — should be skipped
        try await service.indexPage(
            url: URL(string: "https://example.com/swift")!,
            title: "Swift",
            content: content,
            categories: [.web]
        )

        let stats2 = try await service.getStats()
        #expect(stats2.pageCount == stats1.pageCount)
        #expect(stats2.chunkCount == stats1.chunkCount)
    }

    @Test("Content change re-indexes the document")
    func contentChangeReindexes() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/page")!,
            title: "Page",
            content: "Original content about programming in Swift.",
            categories: [.web]
        )

        let stats1 = try await service.getStats()
        #expect(stats1.pageCount == 1)

        // Update with different content
        try await service.indexPage(
            url: URL(string: "https://example.com/page")!,
            title: "Page Updated",
            content: "Completely different content about cooking recipes in the kitchen with food preparation techniques.",
            categories: [.web]
        )

        let stats2 = try await service.getStats()
        #expect(stats2.pageCount == 1)

        // Search should find the new content
        let results = try await service.search(query: "cooking recipes food")
        #expect(!results.isEmpty)
        #expect(results[0].url == "https://example.com/page")
    }

    @Test("Snippet extraction in search results")
    func snippetExtractionInResults() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/article")!,
            title: "Article",
            content: "This is an introduction. Swift programming makes code safe and fast. The conclusion follows.",
            categories: [.web]
        )

        let results = try await service.search(query: "swift programming")
        #expect(!results.isEmpty)
        // Snippet should be non-nil and contain query-relevant text
        if let snippet = results[0].snippet {
            let lower = snippet.lowercased()
            let hasRelevantTerm = lower.contains("swift") || lower.contains("programming")
            #expect(hasRelevantTerm)
        }
    }

    @Test("Category filtering returns only matching documents")
    func categoryFiltering() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/history-page")!,
            title: "History Page",
            content: "Swift programming language code for app development.",
            categories: [.history]
        )
        try await service.indexPage(
            url: URL(string: "https://example.com/web-page")!,
            title: "Web Page",
            content: "Swift programming language code for web development.",
            categories: [.web]
        )

        // Filter to history only
        let results = try await service.search(query: "swift programming", categories: [.history])
        #expect(!results.isEmpty)
        for result in results {
            #expect(result.url == "https://example.com/history-page")
        }
    }

    @Test("Adaptive candidate expansion returns diverse page results")
    func adaptiveCandidateExpansionReturnsUniquePages() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/long-a")!,
            title: "Long Swift Guide A",
            content: makeLongTopicDocument(topic: "swift programming code", uniqueToken: "alpha"),
            categories: [.web]
        )
        try await service.indexPage(
            url: URL(string: "https://example.com/long-b")!,
            title: "Long Swift Guide B",
            content: makeLongTopicDocument(topic: "swift programming code", uniqueToken: "beta"),
            categories: [.web]
        )

        for idx in 1...3 {
            try await service.indexPage(
                url: URL(string: "https://example.com/short-\(idx)")!,
                title: "Short Swift Note \(idx)",
                content: "Swift programming code note \(idx) for app development and clean code practices.",
                categories: [.web]
            )
        }

        let results = try await service.search(query: "swift programming code", limit: 5)
        #expect(results.count == 5)
        #expect(Set(results.map(\.url)).count == 5)
    }

    @Test("Adaptive candidate expansion respects category filtering")
    func adaptiveCandidateExpansionWithCategoryFiltering() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/web-a")!,
            title: "Web Swift Guide A",
            content: makeLongTopicDocument(topic: "swift programming code", uniqueToken: "webalpha"),
            categories: [.web]
        )
        try await service.indexPage(
            url: URL(string: "https://example.com/web-b")!,
            title: "Web Swift Guide B",
            content: makeLongTopicDocument(topic: "swift programming code", uniqueToken: "webbeta"),
            categories: [.web]
        )

        for idx in 1...3 {
            try await service.indexPage(
                url: URL(string: "https://example.com/history-\(idx)")!,
                title: "History Swift Note \(idx)",
                content: "Swift programming code history result \(idx) for app development and language patterns.",
                categories: [.history]
            )
        }

        let results = try await service.search(
            query: "swift programming code",
            categories: [.history],
            limit: 3
        )
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.url.contains("/history-") })
    }

    @Test("clearAll removes all data")
    func clearAllRemovesEverything() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        let service = makeService(tempDir: tempDir)

        try await service.indexPage(
            url: URL(string: "https://example.com/a")!,
            title: "A",
            content: "Swift programming code for development.",
            categories: [.web]
        )
        try await service.indexPage(
            url: URL(string: "https://example.com/b")!,
            title: "B",
            content: "Cooking recipes food in the kitchen.",
            categories: [.web]
        )

        let before = try await service.getStats()
        #expect(before.pageCount == 2)
        #expect(before.chunkCount > 0)

        try await service.clearAll()

        let after = try await service.getStats()
        #expect(after.pageCount == 0)
        #expect(after.chunkCount == 0)
    }
}
