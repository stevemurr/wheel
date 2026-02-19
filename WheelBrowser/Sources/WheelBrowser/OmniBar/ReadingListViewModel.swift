import SwiftUI
import Combine

/// ViewModel for the reading list panel in the OmniBar
@MainActor
class ReadingListViewModel: ObservableObject {
    @Published var items: [SavedPageRecord] = []
    @Published var selectedIndex: Int = -1
    @Published var isLoading = false
    @Published var hasLoaded = false

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.15

    var selectedItem: SavedPageRecord? {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    /// Load all saved pages
    func loadSavedPages() {
        searchTask?.cancel()
        isLoading = true

        searchTask = Task {
            do {
                let database = try SearchDatabase()
                try await database.initialize()
                let pages = try await database.getSavedPages(limit: 100)

                guard !Task.isCancelled else { return }

                items = pages
                selectedIndex = items.isEmpty ? -1 : 0
                isLoading = false
                hasLoaded = true
            } catch {
                print("ReadingListViewModel: Failed to load saved pages: \(error)")
                items = []
                isLoading = false
                hasLoaded = true
            }
        }
    }

    /// Search within saved pages
    func search(query: String) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            loadSavedPages()
            return
        }

        isLoading = true

        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            do {
                let database = try SearchDatabase()
                try await database.initialize()
                let pages = try await database.searchSavedPages(query: query, limit: 50)

                guard !Task.isCancelled else { return }

                items = pages
                selectedIndex = items.isEmpty ? -1 : 0
                isLoading = false
                hasLoaded = true
            } catch {
                print("ReadingListViewModel: Failed to search saved pages: \(error)")
                items = []
                isLoading = false
                hasLoaded = true
            }
        }
    }

    /// Unsave a page by URL
    func unsave(url: URL) {
        Task {
            do {
                let database = try SearchDatabase()
                try await database.initialize()
                try await database.setSaved(url: url.absoluteString, saved: false)

                // Remove from local list
                items.removeAll { $0.url == url }
                if selectedIndex >= items.count {
                    selectedIndex = items.count - 1
                }
            } catch {
                print("ReadingListViewModel: Failed to unsave page: \(error)")
            }
        }
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func clear() {
        items = []
        selectedIndex = -1
        hasLoaded = false
        searchTask?.cancel()
    }
}
