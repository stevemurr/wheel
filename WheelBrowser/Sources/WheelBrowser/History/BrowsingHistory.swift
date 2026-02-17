import Foundation

/// Represents a single history entry
struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let url: String
    let title: String
    let timestamp: Date

    init(url: String, title: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.timestamp = timestamp
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.url == rhs.url
    }
}

/// Manages browsing history with persistence
@MainActor
class BrowsingHistory: ObservableObject {
    static let shared = BrowsingHistory()

    @Published private(set) var entries: [HistoryEntry] = []

    /// Maximum number of history entries to store
    private let maxEntries = 1000

    /// File URL for persisting history
    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("history.json")
    }

    private init() {
        loadHistory()
    }

    /// Add a new entry to history
    func addEntry(url: URL, title: String) {
        let urlString = url.absoluteString

        // Skip certain URLs
        guard shouldRecordURL(urlString) else { return }

        // Remove existing entry with same URL if present (to move it to top)
        entries.removeAll { $0.url == urlString }

        // Create and insert new entry at the beginning
        let entry = HistoryEntry(url: urlString, title: title.isEmpty ? urlString : title)
        entries.insert(entry, at: 0)

        // Trim to max entries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        // Save asynchronously
        Task {
            await saveHistory()
        }
    }

    /// Search history using fuzzy matching
    func search(query: String, limit: Int = 10) -> [HistoryEntry] {
        guard !query.isEmpty else {
            // Return recent entries if no query
            return Array(entries.prefix(limit))
        }

        // Use fuzzy search to score and filter entries
        let scoredEntries = entries.compactMap { entry -> (entry: HistoryEntry, score: Int)? in
            let titleScore = FuzzySearch.score(query: query, target: entry.title)
            let urlScore = FuzzySearch.score(query: query, target: entry.url)

            // Use the better score of title or URL
            let bestScore = max(titleScore, urlScore)

            // Filter out entries with no match
            guard bestScore > 0 else { return nil }

            return (entry, bestScore)
        }

        // Sort by score (descending) and return limited results
        return scoredEntries
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.entry }
    }

    /// Clear all history
    func clearHistory() {
        entries.removeAll()
        Task {
            await saveHistory()
        }
    }

    /// Remove a specific entry
    func removeEntry(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        Task {
            await saveHistory()
        }
    }

    // MARK: - Private Methods

    private func shouldRecordURL(_ urlString: String) -> Bool {
        // Skip blank pages, about pages, etc.
        let skipPrefixes = ["about:", "data:", "javascript:", "blob:"]
        for prefix in skipPrefixes {
            if urlString.hasPrefix(prefix) {
                return false
            }
        }
        return true
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: historyFileURL)
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func saveHistory() async {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}
