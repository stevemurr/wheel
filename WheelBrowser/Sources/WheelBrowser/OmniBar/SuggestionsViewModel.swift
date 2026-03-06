import SwiftUI

/// Constants for search scoring to avoid magic numbers
private enum SearchScoreConstants {
    static let openTabDefault = 1100
    static let exactMatch = 1000
    static let maxTabSuggestionsWhenEmpty = 10
    static let maxTotalSuggestions = 20
}

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

/// Protocol for list-based ViewModels with keyboard selection wrapping
@MainActor
protocol ListSelectable: AnyObject {
    var selectedIndex: Int { get set }
    var selectableCount: Int { get }
}

extension ListSelectable {
    func selectNext() {
        guard selectableCount > 0 else { return }
        if selectedIndex == -1 {
            selectedIndex = 0
        } else {
            selectedIndex = (selectedIndex + 1) % selectableCount
        }
    }

    func selectPrevious() {
        guard selectableCount > 0 else { return }
        if selectedIndex == -1 {
            selectedIndex = selectableCount - 1
        } else {
            selectedIndex = (selectedIndex - 1 + selectableCount) % selectableCount
        }
    }
}

/// View model for managing address bar suggestions
@MainActor
@Observable class SuggestionsViewModel: ListSelectable {
    var suggestions: [Suggestion] = []
    var selectedIndex: Int = -1

    var selectableCount: Int { suggestions.count }

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

        // Search history — returns results with match indices already computed
        let historyResults = history.searchWithMatches(query: query, limit: SearchScoreConstants.maxTotalSuggestions)

        // Exclude URLs that are already shown as open tabs
        let openTabURLs = openTabURLSet(from: allSuggestions)

        for result in historyResults {
            if !openTabURLs.contains(result.entry.url) {
                allSuggestions.append(.history(
                    entry: result.entry,
                    score: result.score,
                    titleMatches: result.titleMatches,
                    urlMatches: result.urlMatches
                ))
            }
        }

        // Sort: open tabs first, then by score
        allSuggestions.sort { a, b in
            if a.isOpenTab && !b.isOpenTab { return true }
            if !a.isOpenTab && b.isOpenTab { return false }
            return a.score > b.score
        }

        allSuggestions = Array(allSuggestions.prefix(SearchScoreConstants.maxTotalSuggestions))

        guard !Task.isCancelled else { return }

        suggestions = allSuggestions
        selectedIndex = -1
    }

    /// Load recent history and open tabs (for when search text is empty)
    func loadRecentHistory() {
        Task { await searchDebouncer.cancel() }

        var allSuggestions: [Suggestion] = []

        // Add open tabs (limited when no query to avoid pushing history off)
        if let browserState = browserState {
            let tabs = Array(browserState.tabs.prefix(SearchScoreConstants.maxTabSuggestionsWhenEmpty))
            for tab in tabs {
                allSuggestions.append(.openTab(tab: tab, score: SearchScoreConstants.openTabDefault))
            }
        }

        let openTabURLs = openTabURLSet(from: allSuggestions)

        // Add recent history entries (excluding open tab URLs)
        for entry in history.entries.prefix(SearchScoreConstants.maxTotalSuggestions) {
            if !openTabURLs.contains(entry.url) {
                allSuggestions.append(.history(entry: entry, score: 0))
            }
        }

        suggestions = Array(allSuggestions.prefix(SearchScoreConstants.maxTotalSuggestions))
        selectedIndex = -1
    }

    /// Search open tabs using fuzzy matching
    private func searchTabs(query: String, tabs: [Tab]) -> [Suggestion] {
        guard !query.isEmpty else {
            return Array(tabs.prefix(SearchScoreConstants.maxTabSuggestionsWhenEmpty))
                .map { .openTab(tab: $0, score: SearchScoreConstants.openTabDefault) }
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
            guard bestScore > 0 else { return nil }

            return .openTab(
                tab: tab,
                score: bestScore,
                titleMatches: titleMatch?.matchedIndices ?? [],
                urlMatches: urlMatch?.matchedIndices ?? []
            )
        }
    }

    /// Extract the set of open tab URLs from suggestions (4D: deduplicated helper)
    private func openTabURLSet(from suggestions: [Suggestion]) -> Set<String> {
        Set(suggestions.compactMap { suggestion -> String? in
            if case .openTab(let tab, _, _, _) = suggestion {
                return tab.url?.absoluteString
            }
            return nil
        })
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
