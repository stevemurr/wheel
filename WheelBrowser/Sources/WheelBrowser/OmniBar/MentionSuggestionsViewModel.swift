import SwiftUI
import Combine

/// ViewModel for managing @ mention suggestions in chat mode
@MainActor
class MentionSuggestionsViewModel: ObservableObject {
    @Published var suggestions: [MentionSuggestion] = []
    @Published var selectedIndex: Int = 0
    @Published var isSearching = false

    /// Reference to browser state for accessing open tabs
    weak var browserState: BrowserState?

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 30_000_000 // 30ms

    /// Currently selected suggestion
    var selectedSuggestion: MentionSuggestion? {
        guard selectedIndex >= 0 && selectedIndex < suggestions.count else { return nil }
        return suggestions[selectedIndex]
    }

    /// Update suggestions based on query, excluding already-added mentions
    /// - Parameters:
    ///   - query: The search query (text after @)
    ///   - excluding: Mentions that should be excluded from results
    ///   - currentTabId: The ID of the current tab (to exclude from tab results)
    func updateSuggestions(
        for query: String,
        excluding: [Mention],
        currentTabId: UUID?
    ) {
        searchTask?.cancel()

        isSearching = true

        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: debounceDelay)
            guard !Task.isCancelled else { return }

            var allSuggestions: [MentionSuggestion] = []

            // Get excluded IDs for filtering
            let excludedIds = Set(excluding.map { $0.id })

            // Add "Current Page" option if not already mentioned
            if !excludedIds.contains(Mention.currentPage.id) {
                let pageScore: Int
                if query.isEmpty {
                    pageScore = 1000 // High score when no query
                } else {
                    // Check if query matches "page", "current", etc.
                    let targets = ["page", "current", "this"]
                    let bestMatch = targets.map { FuzzySearch.score(query: query, target: $0) }.max() ?? 0
                    pageScore = bestMatch > 0 ? bestMatch + 500 : 0 // Boost if matches
                }
                if pageScore > 0 {
                    allSuggestions.append(MentionSuggestion(mention: .currentPage, score: pageScore))
                }
            }

            // Search open tabs
            if let browserState = browserState {
                let tabSuggestions = searchTabs(
                    query: query,
                    tabs: browserState.tabs,
                    excludedIds: excludedIds,
                    currentTabId: currentTabId
                )
                allSuggestions.append(contentsOf: tabSuggestions)
            }

            // Search semantic results (from history)
            let semanticSuggestions = await searchSemanticHistory(
                query: query,
                excludedIds: excludedIds
            )
            allSuggestions.append(contentsOf: semanticSuggestions)

            // Sort by score (higher first), tabs before semantic results at equal score
            allSuggestions.sort { a, b in
                if a.score != b.score {
                    return a.score > b.score
                }
                // Prefer tabs over semantic results
                if case .tab = a.mention, case .semanticResult = b.mention {
                    return true
                }
                return false
            }

            // Limit to 10 results
            allSuggestions = Array(allSuggestions.prefix(10))

            guard !Task.isCancelled else { return }

            suggestions = allSuggestions
            selectedIndex = suggestions.isEmpty ? -1 : 0
            isSearching = false
        }
    }

    /// Search open tabs using fuzzy matching
    private func searchTabs(
        query: String,
        tabs: [Tab],
        excludedIds: Set<String>,
        currentTabId: UUID?
    ) -> [MentionSuggestion] {
        return tabs.compactMap { tab -> MentionSuggestion? in
            // Skip current tab
            if tab.id == currentTabId { return nil }

            let mention = Mention.tab(
                id: tab.id,
                title: tab.title,
                url: tab.url?.absoluteString ?? ""
            )

            // Skip if already mentioned
            if excludedIds.contains(mention.id) { return nil }

            // Calculate score
            let score: Int
            if query.isEmpty {
                score = 500 // Base score for showing all tabs when no query
            } else {
                let titleScore = FuzzySearch.score(query: query, target: tab.title)
                let urlScore: Int
                if let url = tab.url {
                    urlScore = FuzzySearch.score(query: query, target: url.absoluteString)
                } else {
                    urlScore = 0
                }
                score = max(titleScore, urlScore)
            }

            // Filter out non-matches when there's a query
            guard score > 0 else { return nil }

            return MentionSuggestion(mention: mention, score: score)
        }
    }

    /// Search semantic history using the SemanticSearchManager
    private func searchSemanticHistory(
        query: String,
        excludedIds: Set<String>
    ) async -> [MentionSuggestion] {
        guard !query.isEmpty else { return [] }

        let results = await SemanticSearchManager.shared.search(query: query, limit: 5)

        return results.compactMap { result -> MentionSuggestion? in
            // Generate a UUID from the UInt64 id for consistent identification
            let uuid = UUID(uuid: (
                UInt8((result.id >> 56) & 0xFF),
                UInt8((result.id >> 48) & 0xFF),
                UInt8((result.id >> 40) & 0xFF),
                UInt8((result.id >> 32) & 0xFF),
                UInt8((result.id >> 24) & 0xFF),
                UInt8((result.id >> 16) & 0xFF),
                UInt8((result.id >> 8) & 0xFF),
                UInt8(result.id & 0xFF),
                0, 0, 0, 0, 0, 0, 0, 0
            ))
            let mention = Mention.semanticResult(
                id: uuid,
                title: result.page.title,
                url: result.page.url
            )

            // Skip if already mentioned
            if excludedIds.contains(mention.id) { return nil }

            // Convert similarity score (0-1) to integer score (0-500)
            let score = Int(result.score * 500)

            return MentionSuggestion(mention: mention, score: score)
        }
    }

    /// Select the next suggestion (down arrow)
    func selectNext() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex < suggestions.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0 // Wrap to top
        }
    }

    /// Select the previous suggestion (up arrow)
    func selectPrevious() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = suggestions.count - 1 // Wrap to bottom
        }
    }

    /// Clear all suggestions
    func clear() {
        searchTask?.cancel()
        suggestions = []
        selectedIndex = -1
        isSearching = false
    }
}
