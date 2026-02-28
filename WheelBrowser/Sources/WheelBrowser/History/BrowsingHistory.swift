import Foundation

/// Represents a single history entry
struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let url: String
    let title: String
    let timestamp: Date
    let workspaceID: UUID?

    init(url: String, title: String, timestamp: Date = Date(), workspaceID: UUID? = nil) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.timestamp = timestamp
        self.workspaceID = workspaceID
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.url == rhs.url
    }
}

/// Manages browsing history with persistence
/// Uses an index for O(1) URL lookups instead of O(n) array scans
@MainActor
class BrowsingHistory: ObservableObject {
    static let shared = BrowsingHistory()

    @Published private(set) var entries: [HistoryEntry] = []

    /// Index mapping URL strings to their position in the entries array
    /// Enables O(1) lookup for duplicate detection instead of O(n) removeAll
    private var urlIndex: [String: Int] = [:]

    /// Maximum number of history entries to store
    private let maxEntries = 1000

    /// File URL for persisting history
    private var historyFileURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Log.History.error("Could not locate Application Support directory, using temp")
            return FileManager.default.temporaryDirectory.appendingPathComponent("WheelBrowser/history.json")
        }
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("history.json")
    }

    private init() {
        loadHistory()
    }

    /// Add a new entry to history
    /// Uses indexed lookup for O(1) duplicate detection instead of O(n) array scan
    func addEntry(url: URL, title: String, workspaceID: UUID? = nil) {
        let urlString = url.absoluteString

        // Skip certain URLs
        guard shouldRecordURL(urlString) else { return }

        // Check if URL already exists using O(1) index lookup
        if let existingIndex = urlIndex[urlString] {
            // Remove existing entry at the known index
            entries.remove(at: existingIndex)
            // Rebuild index for entries that shifted (only indices >= existingIndex changed)
            rebuildIndexFromPosition(existingIndex)
        }

        // Create and insert new entry at the beginning
        let entry = HistoryEntry(url: urlString, title: title.isEmpty ? urlString : title, workspaceID: workspaceID)
        entries.insert(entry, at: 0)

        // Update index in-place: shift all existing indices by 1 and add new entry at index 0
        for key in urlIndex.keys {
            urlIndex[key, default: 0] += 1
        }
        urlIndex[urlString] = 0

        // Trim to max entries
        if entries.count > maxEntries {
            // Remove entries and their index mappings beyond max
            let removedEntries = entries.suffix(from: maxEntries)
            for entry in removedEntries {
                urlIndex.removeValue(forKey: entry.url)
            }
            entries = Array(entries.prefix(maxEntries))
        }

        // Save asynchronously
        Task {
            await saveHistory()
        }
    }

    /// Rebuilds the URL index starting from a specific position
    /// Called after removing an entry to update shifted indices
    private func rebuildIndexFromPosition(_ startIndex: Int) {
        // Update indices for all entries from startIndex onward
        for i in startIndex..<entries.count {
            urlIndex[entries[i].url] = i
        }
        // Remove stale keys that point beyond the entries array
        urlIndex = urlIndex.filter { $0.value < entries.count }
    }

    /// Search history using fuzzy matching, optionally filtered by workspace
    func search(query: String, workspaceID: UUID? = nil, limit: Int = 10) -> [HistoryEntry] {
        let filteredEntries: [HistoryEntry]
        if let workspaceID = workspaceID {
            filteredEntries = entries.filter { $0.workspaceID == workspaceID }
        } else {
            filteredEntries = entries
        }

        guard !query.isEmpty else {
            // Return recent entries if no query
            return Array(filteredEntries.prefix(limit))
        }

        // Use fuzzy search to score and filter entries
        let scoredEntries = filteredEntries.compactMap { entry -> (entry: HistoryEntry, score: Int)? in
            guard let result = FuzzySearch.bestMatch(query: query, title: entry.title, url: entry.url) else {
                return nil
            }
            return (entry, result.bestScore)
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
        urlIndex.removeAll()
        Task {
            await saveHistory()
        }
    }

    /// Remove a specific entry
    func removeEntry(_ entry: HistoryEntry) {
        if let index = urlIndex[entry.url] {
            entries.remove(at: index)
            urlIndex.removeValue(forKey: entry.url)
            // Update indices for shifted entries
            rebuildIndexFromPosition(index)
        }
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
            // Build index after loading entries
            rebuildFullIndex()
        } catch {
            Log.History.error("Failed to load history", error: error)
        }
    }

    /// Rebuilds the entire URL index from the entries array
    private func rebuildFullIndex() {
        urlIndex.removeAll(keepingCapacity: true)
        for (index, entry) in entries.enumerated() {
            urlIndex[entry.url] = index
        }
    }

    private func saveHistory() async {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            Log.History.error("Failed to save history", error: error)
        }
    }
}
