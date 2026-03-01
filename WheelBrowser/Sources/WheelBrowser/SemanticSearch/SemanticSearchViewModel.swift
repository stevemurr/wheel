import SwiftUI

/// ViewModel for semantic search in the OmniBar
@MainActor
class SemanticSearchViewModel: ObservableObject, ListSelectable {
    @Published var results: [SemanticSearchResult] = []
    @Published var isSearching = false
    @Published var selectedIndex: Int = -1
    @Published var hasSearched = false

    private let searchDebouncer = Debouncer(delay: .milliseconds(300))

    var selectableCount: Int { results.count }

    var selectedResult: SemanticSearchResult? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    func search(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task { await searchDebouncer.cancel() }
            results = []
            selectedIndex = -1
            hasSearched = false
            return
        }

        isSearching = true

        Task {
            await searchDebouncer.debounce { [weak self] in
                await self?.performSearch(for: query)
            }
        }
    }

    /// Perform the actual semantic search (called after debounce)
    private func performSearch(for query: String) async {
        guard !Task.isCancelled else { return }

        let searchResults = await SemanticSearchManagerV2.shared.search(query: query, limit: 20)

        guard !Task.isCancelled else { return }

        results = searchResults
        selectedIndex = results.isEmpty ? -1 : 0
        isSearching = false
        hasSearched = true
    }

    func clear() {
        results = []
        selectedIndex = -1
        hasSearched = false
        Task { await searchDebouncer.cancel() }
    }
}
