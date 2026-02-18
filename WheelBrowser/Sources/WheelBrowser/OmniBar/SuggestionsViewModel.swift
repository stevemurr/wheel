import SwiftUI

/// Represents a suggestion that can be either an open tab or a history entry
enum Suggestion: Identifiable {
    case openTab(tab: Tab, score: Int)
    case history(entry: HistoryEntry, score: Int)

    var id: UUID {
        switch self {
        case .openTab(let tab, _):
            return tab.id
        case .history(let entry, _):
            return entry.id
        }
    }

    var title: String {
        switch self {
        case .openTab(let tab, _):
            return tab.title
        case .history(let entry, _):
            return entry.title
        }
    }

    var url: String {
        switch self {
        case .openTab(let tab, _):
            return tab.url?.absoluteString ?? ""
        case .history(let entry, _):
            return entry.url
        }
    }

    var score: Int {
        switch self {
        case .openTab(_, let score):
            return score
        case .history(_, let score):
            return score
        }
    }

    var isOpenTab: Bool {
        if case .openTab = self { return true }
        return false
    }

    /// Returns the tab ID if this is an open tab suggestion
    var tabId: UUID? {
        if case .openTab(let tab, _) = self {
            return tab.id
        }
        return nil
    }

    /// Returns the timestamp for sorting (open tabs use current time)
    var timestamp: Date {
        switch self {
        case .openTab:
            return Date() // Open tabs are considered "current"
        case .history(let entry, _):
            return entry.timestamp
        }
    }
}

/// View model for managing address bar suggestions
@MainActor
class SuggestionsViewModel: ObservableObject {
    @Published var suggestions: [Suggestion] = []
    @Published var selectedIndex: Int = -1

    /// Reference to browser state for accessing open tabs
    weak var browserState: BrowserState?

    private let history = BrowsingHistory.shared
    private var searchTask: Task<Void, Never>?

    /// Update suggestions based on user input
    func updateSuggestions(for query: String) {
        // Cancel any pending search
        searchTask?.cancel()

        // Debounce the search for performance
        searchTask = Task {
            // Small delay to debounce rapid typing
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            guard !Task.isCancelled else { return }

            var allSuggestions: [Suggestion] = []

            // Search open tabs first
            if let browserState = browserState {
                let tabSuggestions = searchTabs(query: query, tabs: browserState.tabs)
                allSuggestions.append(contentsOf: tabSuggestions)
            }

            // Search history (empty query returns recent entries)
            let historyResults = history.search(query: query, limit: 20)

            // Convert history results to suggestions, excluding URLs that are already open tabs
            let openTabURLs = Set(allSuggestions.compactMap { suggestion -> String? in
                if case .openTab(let tab, _) = suggestion {
                    return tab.url?.absoluteString
                }
                return nil
            })

            for entry in historyResults {
                // Skip if this URL is already shown as an open tab
                if !openTabURLs.contains(entry.url) {
                    // Calculate score for consistent ordering
                    let titleScore = FuzzySearch.score(query: query, target: entry.title)
                    let urlScore = FuzzySearch.score(query: query, target: entry.url)
                    let bestScore = max(titleScore, urlScore)
                    allSuggestions.append(.history(entry: entry, score: bestScore))
                }
            }

            // Sort all suggestions: open tabs first (sorted by score), then history (by score)
            allSuggestions.sort { a, b in
                // Open tabs always come first
                if a.isOpenTab && !b.isOpenTab { return true }
                if !a.isOpenTab && b.isOpenTab { return false }
                // Within the same category, sort by score (higher first)
                return a.score > b.score
            }

            // Limit total suggestions
            allSuggestions = Array(allSuggestions.prefix(20))

            guard !Task.isCancelled else { return }

            suggestions = allSuggestions
            selectedIndex = -1
        }
    }

    /// Load recent history and open tabs (for when search text is empty)
    func loadRecentHistory() {
        searchTask?.cancel()

        var allSuggestions: [Suggestion] = []

        // Add all open tabs first
        if let browserState = browserState {
            for tab in browserState.tabs {
                allSuggestions.append(.openTab(tab: tab, score: 1000)) // High score for open tabs
            }
        }

        // Get open tab URLs to filter history
        let openTabURLs = Set(allSuggestions.compactMap { suggestion -> String? in
            if case .openTab(let tab, _) = suggestion {
                return tab.url?.absoluteString
            }
            return nil
        })

        // Add recent history entries (excluding open tab URLs)
        for entry in history.entries.prefix(20) {
            if !openTabURLs.contains(entry.url) {
                allSuggestions.append(.history(entry: entry, score: 0))
            }
        }

        // Limit total and update
        suggestions = Array(allSuggestions.prefix(20))
        selectedIndex = -1
    }

    /// Search open tabs using fuzzy matching
    private func searchTabs(query: String, tabs: [Tab]) -> [Suggestion] {
        guard !query.isEmpty else {
            // Return all tabs when query is empty
            return tabs.map { .openTab(tab: $0, score: 1000) }
        }

        return tabs.compactMap { tab -> Suggestion? in
            let titleScore = FuzzySearch.score(query: query, target: tab.title)
            let urlScore: Int
            if let url = tab.url {
                urlScore = FuzzySearch.score(query: query, target: url.absoluteString)
            } else {
                urlScore = 0
            }

            let bestScore = max(titleScore, urlScore)

            // Filter out tabs with no match
            guard bestScore > 0 else { return nil }

            return .openTab(tab: tab, score: bestScore)
        }
    }

    /// Select the next suggestion (down arrow)
    func selectNext() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex == -1 {
            selectedIndex = 0
        } else if selectedIndex < suggestions.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0 // Wrap
        }
    }

    /// Select the previous suggestion (up arrow)
    func selectPrevious() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex == -1 {
            selectedIndex = suggestions.count - 1
        } else if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = suggestions.count - 1 // Wrap
        }
    }

    /// Get the currently selected suggestion, if any
    var selectedSuggestion: Suggestion? {
        guard selectedIndex >= 0 && selectedIndex < suggestions.count else { return nil }
        return suggestions[selectedIndex]
    }

    /// Hide suggestions
    func hide() {
        selectedIndex = -1
    }

    /// Clear all suggestions
    func clear() {
        suggestions = []
        selectedIndex = -1
    }
}
