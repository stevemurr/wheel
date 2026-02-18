import Foundation

/// Background indexing pipeline for semantic search
actor IndexingPipeline {
    private let db: SearchDatabase
    private let embeddingService: any EmbeddingService

    private let chunkSize = 500      // approximate tokens per chunk
    private let chunkOverlap = 50    // overlap between chunks

    private var isProcessing = false
    private var pendingQueue: [(pageId: Int64, content: String)] = []

    init(db: SearchDatabase, embeddingService: any EmbeddingService) {
        self.db = db
        self.embeddingService = embeddingService
    }

    /// Index a page that was just visited
    func indexPage(url: URL, title: String?, content: String, workspaceID: UUID? = nil) async throws {
        // Upsert page record
        let pageId = try await db.upsertPage(url: url, title: title, workspaceID: workspaceID)

        // Update content
        try await db.updatePageContent(pageId: pageId, title: title, fullText: content)

        // Queue for embedding generation
        pendingQueue.append((pageId, content))

        // Process queue if not already processing
        if !isProcessing {
            await processQueue()
        }
    }

    /// Process pending pages in the background
    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true

        defer { isProcessing = false }

        while !pendingQueue.isEmpty {
            let (pageId, content) = pendingQueue.removeFirst()

            do {
                try await processPage(pageId: pageId, content: content)
            } catch {
                print("Failed to process page \(pageId): \(error)")
            }
        }
    }

    /// Process a single page: chunk, embed, store
    private func processPage(pageId: Int64, content: String) async throws {
        print("IndexingPipeline: Processing page \(pageId)")

        print("IndexingPipeline: Getting page from db...")
        guard let page = try await db.getPage(id: pageId) else {
            print("IndexingPipeline: Page \(pageId) not found")
            return
        }
        print("IndexingPipeline: Got page: \(page.title ?? "untitled")")

        // Stage 1: Chunk the content
        let chunks = chunkText(content)
        print("IndexingPipeline: Created \(chunks.count) chunks")

        // Stage 2: Generate embeddings for all chunks + title
        let textsToEmbed = [page.title ?? ""] + chunks
        print("IndexingPipeline: Generating embeddings for \(textsToEmbed.count) texts...")
        let embeddings = try await embeddingService.embed(texts: textsToEmbed)
        print("IndexingPipeline: Got \(embeddings.count) embeddings, dim=\(embeddings.first?.count ?? 0)")

        let titleEmbedding = embeddings[0]
        let chunkEmbeddings = Array(embeddings.dropFirst())

        // Stage 3: Store title embedding
        print("IndexingPipeline: Storing title embedding...")
        try await db.updatePageTitleEmbedding(pageId: pageId, embedding: titleEmbedding)
        print("IndexingPipeline: Title embedding stored")

        // Stage 4: Store chunks
        print("IndexingPipeline: Storing \(chunks.count) chunks...")
        try await db.insertChunks(pageId: pageId, chunks: chunks, embeddings: chunkEmbeddings)
        print("IndexingPipeline: Chunks stored, checking integrity...")
        try await db.checkIntegrity()
        print("IndexingPipeline: Integrity OK after chunks")

        // Stage 5: Generate summary embedding (use first chunk as summary for now)
        // In production, you'd call an LLM to generate a proper summary
        let summaryText = chunks.first ?? page.title ?? ""
        print("IndexingPipeline: Generating summary embedding...")
        let summaryEmbedding = try await embeddingService.embed(text: summaryText)
        print("IndexingPipeline: Storing summary...")
        try await db.updatePageSummary(pageId: pageId, summary: summaryText, embedding: summaryEmbedding)
        print("IndexingPipeline: Summary stored")

        // Mark as complete
        try await db.markEmbeddingsGenerated(pageId: pageId)
        print("IndexingPipeline: Page \(pageId) complete")
    }

    /// Process any pending pages from previous sessions
    func processPendingPages() async {
        do {
            let pending = try await db.getPendingPages(limit: 50)
            for page in pending {
                if let content = page.fullText {
                    pendingQueue.append((page.id, content))
                }
            }

            if !pendingQueue.isEmpty && !isProcessing {
                await processQueue()
            }
        } catch {
            print("Failed to fetch pending pages: \(error)")
        }
    }

    /// Chunk text into overlapping segments
    private func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []

        // Split into sentences (rough approximation)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var currentChunk = ""
        var currentWordCount = 0

        for sentence in sentences {
            let sentenceWordCount = sentence.split(separator: " ").count

            // If adding this sentence exceeds chunk size, save current chunk
            if currentWordCount + sentenceWordCount > chunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))

                // Keep overlap from end of current chunk
                let words = currentChunk.split(separator: " ")
                if words.count > chunkOverlap {
                    currentChunk = words.suffix(chunkOverlap).joined(separator: " ") + " "
                    currentWordCount = chunkOverlap
                } else {
                    currentChunk = ""
                    currentWordCount = 0
                }
            }

            currentChunk += sentence + ". "
            currentWordCount += sentenceWordCount
        }

        // Don't forget the last chunk
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // If no chunks were created, just return the whole text
        if chunks.isEmpty && !text.isEmpty {
            chunks.append(String(text.prefix(2000)))
        }

        return chunks
    }

    /// Get current stats
    func getStats() async throws -> SearchStats {
        try await db.getStats()
    }
}
