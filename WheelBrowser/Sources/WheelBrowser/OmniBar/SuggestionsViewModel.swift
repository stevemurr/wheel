import SwiftUI

/// View model for managing address bar suggestions
@MainActor
class SuggestionsViewModel: ObservableObject {
    @Published var suggestions: [HistoryEntry] = []
    @Published var selectedIndex: Int = -1

    private let history = BrowsingHistory.shared
    private var searchTask: Task<Void, Never>?

    /// Update suggestions based on user input
    func updateSuggestions(for query: String) {
        // Cancel any pending search
        searchTask?.cancel()

        guard !query.isEmpty else {
            suggestions = []
            selectedIndex = -1
            return
        }

        // Debounce the search for performance
        searchTask = Task {
            // Small delay to debounce rapid typing
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            guard !Task.isCancelled else { return }

            let results = history.search(query: query, limit: 8)

            guard !Task.isCancelled else { return }

            suggestions = results
            selectedIndex = -1
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
    var selectedSuggestion: HistoryEntry? {
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
