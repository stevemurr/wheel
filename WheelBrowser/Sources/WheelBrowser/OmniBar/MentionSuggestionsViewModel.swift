import SwiftUI

/// ViewModel for managing @ mention suggestions in chat mode
@MainActor
@Observable class MentionSuggestionsViewModel: ListSelectable {
    var suggestions: [MentionSuggestion] = []
    var selectedIndex: Int = -1
    var isSearching = false

    var selectableCount: Int { suggestions.count }

    /// Reference to browser state for accessing open tabs
    weak var browserState: BrowserState?
    weak var noteStore: NoteStore?

    private let searchDebouncer = Debouncer(delay: .milliseconds(30))

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
        isSearching = true

        Task {
            await searchDebouncer.debounce { [weak self] in
                await self?.performSearch(for: query, excluding: excluding, currentTabId: currentTabId)
            }
        }
    }

    /// Perform the actual mention search (called after debounce)
    private func performSearch(
        for query: String,
        excluding: [Mention],
        currentTabId: UUID?
    ) async {
        guard !Task.isCancelled else { return }

        var allSuggestions: [MentionSuggestion] = []

        // Get excluded IDs for filtering
        let excludedIds = Set(excluding.map { $0.id })

        // Check if there are open overlay windows (mini windows should be default when present)
        let hasOpenOverlays = !OverlayWindowManager.shared.windows.isEmpty

        // Add "Current Page" option if not already mentioned
        if !excludedIds.contains(Mention.currentPage.id) {
            let pageScore: Int
            if query.isEmpty {
                // Lower score when overlays are open so they become the default
                pageScore = hasOpenOverlays ? 950 : 1000
            } else {
                let targets = ["page", "current", "this"]
                let bestMatch = targets.map { FuzzySearch.score(query: query, target: $0) }.max() ?? 0
                pageScore = bestMatch > 0 ? bestMatch + 500 : 0
            }
            if pageScore > 0 {
                allSuggestions.append(MentionSuggestion(mention: .currentPage, score: pageScore))
            }
        }

        // Add "History" option if not already mentioned
        if !excludedIds.contains(Mention.history.id) {
            let historyScore: Int
            if query.isEmpty {
                historyScore = 900
            } else {
                let targets = ["history", "search", "find", "past", "browsing"]
                let bestMatch = targets.map { FuzzySearch.score(query: query, target: $0) }.max() ?? 0
                historyScore = bestMatch > 0 ? bestMatch + 400 : 0
            }
            if historyScore > 0 {
                allSuggestions.append(MentionSuggestion(mention: .history, score: historyScore))
            }
        }

        // Add "Web" option if not already mentioned
        if !excludedIds.contains(Mention.web.id) {
            let webScore: Int
            if query.isEmpty {
                webScore = 850
            } else {
                let targets = ["web", "all", "pages", "sites", "internet"]
                let bestMatch = targets.map { FuzzySearch.score(query: query, target: $0) }.max() ?? 0
                webScore = bestMatch > 0 ? bestMatch + 350 : 0
            }
            if webScore > 0 {
                allSuggestions.append(MentionSuggestion(mention: .web, score: webScore))
            }
        }

        // Add "Reading List" option if not already mentioned
        if !excludedIds.contains(Mention.readingList.id) {
            let readingListScore: Int
            if query.isEmpty {
                readingListScore = 800
            } else {
                let targets = ["reading", "list", "saved", "bookmarks", "later"]
                let bestMatch = targets.map { FuzzySearch.score(query: query, target: $0) }.max() ?? 0
                readingListScore = bestMatch > 0 ? bestMatch + 300 : 0
            }
            if readingListScore > 0 {
                allSuggestions.append(MentionSuggestion(mention: .readingList, score: readingListScore))
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

        if let noteStore {
            let noteSuggestions = searchNotes(
                query: query,
                notes: noteStore.orderedNotes,
                excludedIds: excludedIds
            )
            allSuggestions.append(contentsOf: noteSuggestions)
        }

        // Search open overlay windows (mini windows)
        let overlaySuggestions = searchOverlays(
            query: query,
            overlays: OverlayWindowManager.shared.windows,
            excludedIds: excludedIds
        )
        allSuggestions.append(contentsOf: overlaySuggestions)

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
            return suggestionRank(for: a.mention) < suggestionRank(for: b.mention)
        }

        allSuggestions = Array(allSuggestions.prefix(10))

        guard !Task.isCancelled else { return }

        suggestions = allSuggestions
        selectedIndex = suggestions.isEmpty ? -1 : 0
        isSearching = false
    }

    private func searchNotes(
        query: String,
        notes: [NoteRecord],
        excludedIds: Set<String>
    ) -> [MentionSuggestion] {
        return notes.enumerated().compactMap { index, note -> MentionSuggestion? in
            let mention = Mention.note(
                id: note.id,
                title: note.displayTitle,
                excerpt: note.excerpt
            )

            if excludedIds.contains(mention.id) { return nil }

            let score: Int
            if query.isEmpty {
                score = max(620 - (index * 8), 0)
            } else {
                let fullText = note.document.plainText(maxLength: Int.max)
                let titleScore = FuzzySearch.score(query: query, target: note.displayTitle)
                let excerptScore = FuzzySearch.score(query: query, target: note.excerpt)
                let contentScore = FuzzySearch.score(query: query, target: fullText)
                let typeScore = ["note", "memo", "scratchpad"]
                    .map { FuzzySearch.score(query: query, target: $0) }
                    .max() ?? 0
                score = max(titleScore, excerptScore, contentScore, typeScore)
            }

            guard score > 0 else { return nil }
            return MentionSuggestion(mention: mention, score: score)
        }
    }

    private func suggestionRank(for mention: Mention) -> Int {
        switch mention {
        case .overlay:
            return 0
        case .currentPage:
            return 1
        case .history, .web, .readingList, .domain:
            return 2
        case .note:
            return 3
        case .tab:
            return 4
        case .semanticResult:
            return 5
        }
    }

    /// Search open overlay windows using fuzzy matching
    private func searchOverlays(
        query: String,
        overlays: [OverlayWindowItem],
        excludedIds: Set<String>
    ) -> [MentionSuggestion] {
        // When overlays exist, make them the default (score 1000+)
        // Most recent overlay gets highest score
        let sortedOverlays = overlays.sorted { $0.createdAt > $1.createdAt }

        return sortedOverlays.enumerated().compactMap { index, overlay -> MentionSuggestion? in
            let mention = Mention.overlay(
                id: overlay.id,
                title: overlay.title,
                url: overlay.url.absoluteString
            )

            // Skip if already mentioned
            if excludedIds.contains(mention.id) { return nil }

            // Calculate score
            let score: Int
            if query.isEmpty {
                // Most recent overlay gets score 1000 (becomes default)
                // Subsequent overlays get decreasing scores but still above Page (900)
                score = 1000 - (index * 10)
            } else {
                let titleScore = FuzzySearch.score(query: query, target: overlay.title)
                let urlScore = FuzzySearch.score(query: query, target: overlay.url.absoluteString)
                // Also match "mini", "window", "overlay", "pip"
                let typeScore = ["mini", "window", "overlay", "pip", "popup"]
                    .map { FuzzySearch.score(query: query, target: $0) }
                    .max() ?? 0
                score = max(titleScore, urlScore, typeScore)
            }

            // Filter out non-matches when there's a query
            guard score > 0 else { return nil }

            return MentionSuggestion(mention: mention, score: score)
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

    /// Search semantic history using the SemanticSearchManagerV2
    private func searchSemanticHistory(
        query: String,
        excludedIds: Set<String>
    ) async -> [MentionSuggestion] {
        guard !query.isEmpty else { return [] }

        let results = await SemanticSearchManagerV2.shared.search(query: query, limit: 5)

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

    /// Clear all suggestions
    func clear() {
        Task { await searchDebouncer.cancel() }
        suggestions = []
        selectedIndex = -1
        isSearching = false
    }
}
