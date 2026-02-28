import SwiftUI

/// Represents a suggestion that can be either an open tab or a history entry
enum Suggestion: Identifiable {
    case openTab(tab: Tab, score: Int, titleMatches: [Int] = [], urlMatches: [Int] = [])
    case history(entry: HistoryEntry, score: Int, titleMatches: [Int] = [], urlMatches: [Int] = [])

    var id: UUID {
        switch self {
        case .openTab(let tab, _, _, _):
            return tab.id
        case .history(let entry, _, _, _):
            return entry.id
        }
    }

    var title: String {
        switch self {
        case .openTab(let tab, _, _, _):
            return tab.title
        case .history(let entry, _, _, _):
            return entry.title
        }
    }

    var url: String {
        switch self {
        case .openTab(let tab, _, _, _):
            return tab.url?.absoluteString ?? ""
        case .history(let entry, _, _, _):
            return entry.url
        }
    }

    var score: Int {
        switch self {
        case .openTab(_, let score, _, _):
            return score
        case .history(_, let score, _, _):
            return score
        }
    }

    var titleMatches: [Int] {
        switch self {
        case .openTab(_, _, let matches, _):
            return matches
        case .history(_, _, let matches, _):
            return matches
        }
    }

    var urlMatches: [Int] {
        switch self {
        case .openTab(_, _, _, let matches):
            return matches
        case .history(_, _, _, let matches):
            return matches
        }
    }

    var isOpenTab: Bool {
        if case .openTab = self { return true }
        return false
    }

    /// Returns the tab ID if this is an open tab suggestion
    var tabId: UUID? {
        if case .openTab(let tab, _, _, _) = self {
            return tab.id
        }
        return nil
    }

    /// Returns the timestamp for sorting (open tabs use current time)
    var timestamp: Date {
        switch self {
        case .openTab:
            return Date() // Open tabs are considered "current"
        case .history(let entry, _, _, _):
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
    private let searchDebouncer = Debouncer(delay: .milliseconds(50))

    /// Update suggestions based on user input
    func updateSuggestions(for query: String) {
        Task {
            await searchDebouncer.debounce { [weak self] in
                await self?.performSearch(for: query)
            }
        }
    }

    /// Perform the actual search (called after debounce)
    private func performSearch(for query: String) async {
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
                if case .openTab(let tab, _, _, _) = suggestion {
                    return tab.url?.absoluteString
                }
                return nil
            })

            for entry in historyResults {
                // Skip if this URL is already shown as an open tab
                if !openTabURLs.contains(entry.url) {
                    let result = FuzzySearch.bestMatch(query: query, title: entry.title, url: entry.url)
                    allSuggestions.append(.history(
                        entry: entry,
                        score: result?.bestScore ?? 0,
                        titleMatches: result?.titleMatch?.matchedIndices ?? [],
                        urlMatches: result?.urlMatch?.matchedIndices ?? []
                    ))
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

    /// Load recent history and open tabs (for when search text is empty)
    func loadRecentHistory() {
        Task { await searchDebouncer.cancel() }

        var allSuggestions: [Suggestion] = []

        // Add all open tabs first
        if let browserState = browserState {
            for tab in browserState.tabs {
                allSuggestions.append(.openTab(tab: tab, score: 1000)) // High score for open tabs
            }
        }

        // Get open tab URLs to filter history
        let openTabURLs = Set(allSuggestions.compactMap { suggestion -> String? in
            if case .openTab(let tab, _, _, _) = suggestion {
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
            let titleMatch = FuzzySearch.match(query: query, target: tab.title)
            let urlMatch: FuzzyMatch?
            if let url = tab.url {
                urlMatch = FuzzySearch.match(query: query, target: url.absoluteString)
            } else {
                urlMatch = nil
            }

            let bestScore = max(titleMatch?.score ?? 0, urlMatch?.score ?? 0)

            // Filter out tabs with no match
            guard bestScore > 0 else { return nil }

            return .openTab(
                tab: tab,
                score: bestScore,
                titleMatches: titleMatch?.matchedIndices ?? [],
                urlMatches: urlMatch?.matchedIndices ?? []
            )
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
