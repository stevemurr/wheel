import SwiftUI

/// Panel content for the reading list mode in OmniBar
struct ReadingListPanelContent: View {
    var viewModel: ReadingListViewModel
    let searchText: String
    let onSelect: (SavedPageRecord) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if viewModel.items.isEmpty {
                        if viewModel.isLoading {
                            loadingState
                                .padding(.top, 30)
                        } else if viewModel.hasLoaded {
                            if searchText.isEmpty {
                                emptyStateNoSaved
                                    .padding(.top, 30)
                            } else {
                                emptyStateNoResults
                                    .padding(.top, 30)
                            }
                        }
                    } else {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            ReadingListRow(
                                item: item,
                                isSelected: index == viewModel.selectedIndex,
                                onSelect: { onSelect(item) },
                                onRemove: { viewModel.unsave(url: item.url) }
                            )
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < viewModel.items.count {
                    let selectedId = viewModel.items[newIndex].id
                    withAnimation(AppAnimation.quickOut) {
                        proxy.scrollTo(selectedId, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyStateNoSaved: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 24))
                .foregroundColor(.purple)

            VStack(spacing: 4) {
                Text("Reading List Empty")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text("Press Cmd+S to save pages for later")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyStateNoResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No matches found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text("Try different search terms")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading saved pages...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Reading List Row

struct ReadingListRow: View {
    let item: SavedPageRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var showRemoveButton = false

    private var domain: String {
        item.url.cleanDomain
    }

    private var savedDateString: String {
        item.savedAt.abbreviatedRelativeTimeString()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Favicon
            faviconView
                .frame(width: 28, height: 28)

            // Title and URL
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !item.snippet.isEmpty {
                    Text(item.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(domain)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)

                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("Saved \(savedDateString)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            // Remove button (shows on hover)
            if isHovering || showRemoveButton {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.purple.opacity(0.2)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color.clear
    }

    @ViewBuilder
    private var faviconView: some View {
        if !domain.isEmpty {
            let initial = String(domain.prefix(1)).uppercased()
            Text(initial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorForDomain(domain))
                )
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    private func colorForDomain(_ domain: String) -> Color {
        DomainColor.color(for: domain)
    }
}

// MARK: - Reading List ViewModel

/// ViewModel for the reading list panel in the OmniBar
@MainActor
@Observable class ReadingListViewModel: ListSelectable {
    var items: [SavedPageRecord] = []
    var selectedIndex: Int = -1
    var isLoading = false
    var hasLoaded = false

    var selectableCount: Int { items.count }

    private let searchDebouncer = Debouncer(delay: .milliseconds(150))

    var selectedItem: SavedPageRecord? {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    /// Load all saved pages
    func loadSavedPages() {
        Task { await searchDebouncer.cancel() }
        isLoading = true

        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let pages = try await database.getSavedPages(limit: 100)

                guard !Task.isCancelled else { return }

                items = pages
                selectedIndex = items.isEmpty ? -1 : 0
                isLoading = false
                hasLoaded = true
            } catch {
                Log.OmniBar.error("ReadingListViewModel: Failed to load saved pages", error: error)
                items = []
                isLoading = false
                hasLoaded = true
            }
        }
    }

    /// Search within saved pages
    func search(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            loadSavedPages()
            return
        }

        isLoading = true

        Task {
            await searchDebouncer.debounce { [weak self] in
                await self?.performSearch(for: query)
            }
        }
    }

    /// Perform the actual search (called after debounce)
    private func performSearch(for query: String) async {
        guard !Task.isCancelled else { return }

        do {
            let database = SearchDatabase.shared
            try await database.initialize()
            let pages = try await database.searchSavedPages(query: query, limit: 50)

            guard !Task.isCancelled else { return }

            items = pages
            selectedIndex = items.isEmpty ? -1 : 0
            isLoading = false
            hasLoaded = true
        } catch {
            Log.OmniBar.error("ReadingListViewModel: Failed to search saved pages", error: error)
            items = []
            isLoading = false
            hasLoaded = true
        }
    }

    /// Unsave a page by URL
    func unsave(url: URL) {
        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                try await database.setSaved(url: url.absoluteString, saved: false)

                // Remove from local list
                items.removeAll { $0.url == url }
                if selectedIndex >= items.count {
                    selectedIndex = items.count - 1
                }
            } catch {
                Log.OmniBar.error("ReadingListViewModel: Failed to unsave page", error: error)
            }
        }
    }

    func clear() {
        items = []
        selectedIndex = -1
        hasLoaded = false
        Task { await searchDebouncer.cancel() }
    }
}
