import Fabric
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
    var fabricClient: (any WheelFabricMentionClient)?

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

        if let fabricSuggestions = await searchFabricResources(
            query: query,
            excludedIds: excludedIds,
            currentTabId: currentTabId,
            hasOpenOverlays: hasOpenOverlays
        ) {
            allSuggestions.append(contentsOf: fabricSuggestions)
        } else {
            if !excludedIds.contains(Mention.currentPage.id),
               let currentPageSuggestion = currentPageSuggestion(
                query: query,
                hasOpenOverlays: hasOpenOverlays
               ) {
                allSuggestions.append(currentPageSuggestion)
            }

            if let browserState = browserState {
                if let pageSnapshotSuggestion = currentPageSnapshotSuggestion(
                    query: query,
                    browserState: browserState,
                    currentTabId: currentTabId,
                    hasOpenOverlays: hasOpenOverlays,
                    excludedIds: excludedIds
                ) {
                    allSuggestions.append(pageSnapshotSuggestion)
                }

                let tabSuggestions = searchTabs(
                    query: query,
                    tabs: browserState.tabs,
                    excludedIds: excludedIds,
                    currentTabId: currentTabId
                )
                allSuggestions.append(contentsOf: tabSuggestions)
            }
        }

        // Search open overlay windows (mini windows)
        let overlaySuggestions = searchOverlays(
            query: query,
            overlays: OverlayWindowManager.shared.windows,
            excludedIds: excludedIds
        )
        allSuggestions.append(contentsOf: overlaySuggestions)

        guard !Task.isCancelled else { return }

        applySuggestions(allSuggestions, isSearching: !query.isEmpty)

        guard !query.isEmpty else { return }

        let semanticSuggestions = await searchSemanticHistory(
            query: query,
            excludedIds: excludedIds
        )

        guard !Task.isCancelled else { return }

        allSuggestions.append(contentsOf: semanticSuggestions)
        applySuggestions(allSuggestions, isSearching: false)
    }

    private func applySuggestions(_ suggestions: [MentionSuggestion], isSearching: Bool) {
        var sortedSuggestions = suggestions
        sortedSuggestions.sort { a, b in
            if a.score != b.score {
                return a.score > b.score
            }
            return suggestionRank(for: a.mention) < suggestionRank(for: b.mention)
        }

        self.suggestions = Array(sortedSuggestions.prefix(10))
        selectedIndex = self.suggestions.isEmpty ? -1 : 0
        self.isSearching = isSearching
    }

    private func currentPageSuggestion(
        query: String,
        hasOpenOverlays: Bool
    ) -> MentionSuggestion? {
        let score: Int
        if query.isEmpty {
            // Lower score when overlays are open so they become the default.
            score = hasOpenOverlays ? 950 : 1000
        } else {
            let targets = ["page", "current", "this"]
            let bestMatch = targets.map { FuzzySearch.score(query: query, target: $0) }.max() ?? 0
            score = bestMatch > 0 ? bestMatch + 500 : 0
        }

        guard score > 0 else { return nil }
        return MentionSuggestion(mention: .currentPage, score: score)
    }

    private func currentPageSnapshotSuggestion(
        query: String,
        browserState: BrowserState,
        currentTabId: UUID?,
        hasOpenOverlays: Bool,
        excludedIds: Set<String>
    ) -> MentionSuggestion? {
        let snapshotTab = currentTabId.flatMap(browserState.tab(for:))
            ?? browserState.activeTab
        guard let snapshotTab,
              let url = snapshotTab.url?.absoluteString else {
            return nil
        }

        let mention = Mention.pageSnapshot(
            id: snapshotTab.id,
            title: snapshotTab.displayTitle,
            url: url
        )
        guard !excludedIds.contains(mention.id) else {
            return nil
        }

        let score: Int
        if query.isEmpty {
            score = hasOpenOverlays ? 940 : 975
        } else {
            let titleScore = FuzzySearch.score(query: query, target: snapshotTab.displayTitle)
            let urlScore = FuzzySearch.score(query: query, target: url)
            let typeScore = ["snapshot", "capture", "page snapshot", "frozen page"]
                .map { FuzzySearch.score(query: query, target: $0) }
                .max() ?? 0
            score = max(titleScore, urlScore, typeScore)
        }

        guard score > 0 else { return nil }
        return MentionSuggestion(mention: mention, score: score)
    }

    private func searchFabricResources(
        query: String,
        excludedIds: Set<String>,
        currentTabId: UUID?,
        hasOpenOverlays: Bool
    ) async -> [MentionSuggestion]? {
        guard let fabricClient else {
            return nil
        }

        do {
            let resources = try await fabricClient.discoverResources(
                callerAppID: WheelFabricAppID.chat,
                query: nil
            )

            return resources.enumerated().compactMap { index, resource in
                if resource.uri.appID == WheelFabricAppID.notes,
                   resource.kind == "note",
                   let workspaceID = resource.metadata["workspaceID"]?.stringValue.flatMap(UUID.init(uuidString:)),
                   let currentWorkspaceID = browserState?.currentWorkspaceId,
                   workspaceID != currentWorkspaceID {
                    return nil
                }

                guard let mention = Mention.fabricBackedMention(
                    from: resource,
                    currentTabID: currentTabId
                ) else {
                    return nil
                }

                guard !excludedIds.contains(mention.id) else {
                    return nil
                }

                let score = fabricSuggestionScore(
                    for: resource,
                    query: query,
                    hasOpenOverlays: hasOpenOverlays,
                    ordinal: index
                )
                guard score > 0 else {
                    return nil
                }

                return MentionSuggestion(mention: mention, score: score)
            }
        } catch {
            return nil
        }
    }

    private func fabricSuggestionScore(
        for resource: FabricResourceDescriptor,
        query: String,
        hasOpenOverlays: Bool,
        ordinal: Int
    ) -> Int {
        if query.isEmpty {
            switch resource.kind {
            case "page":
                return hasOpenOverlays ? 950 : 1000
            case "page-snapshot":
                return hasOpenOverlays ? 940 : 975
            case "note":
                return max(620 - (ordinal * 8), 0)
            case "tab":
                return 500
            default:
                return 0
            }
        }

        let titleScore = FuzzySearch.score(query: query, target: resource.title)
        let summaryScore = FuzzySearch.score(query: query, target: resource.summary)
        let subtitleScore = FuzzySearch.score(
            query: query,
            target: resource.presentation?.subtitle ?? ""
        )
        let urlScore = FuzzySearch.score(
            query: query,
            target: resource.metadata["url"]?.stringValue ?? ""
        )
        let categoryScore = FuzzySearch.score(
            query: query,
            target: resource.presentation?.categoryLabel ?? ""
        )

        let typeTargets: [String]
        switch resource.kind {
        case "page":
            typeTargets = ["page", "current", "this"]
        case "page-snapshot":
            typeTargets = ["snapshot", "capture", "page snapshot", "frozen page"]
        case "tab":
            typeTargets = ["tab", "page"]
        case "note":
            typeTargets = ["note", "memo", "scratchpad"]
        default:
            typeTargets = [resource.kind]
        }

        let typeScore = typeTargets
            .map { FuzzySearch.score(query: query, target: $0) }
            .max() ?? 0

        return max(titleScore, summaryScore, subtitleScore, urlScore, categoryScore, typeScore)
    }

    private func suggestionRank(for mention: Mention) -> Int {
        switch mention {
        case .overlay:
            return 0
        case .currentPage:
            return 1
        case .pageSnapshot:
            return 2
        case .history, .web, .readingList, .domain:
            return 3
        case .note:
            return 4
        case .tab:
            return 5
        case .semanticResult:
            return 6
        case .fabricResource:
            return 7
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
