import SwiftUI
import Combine

/// ViewModel for semantic search in the OmniBar
@MainActor
class SemanticSearchViewModel: ObservableObject {
    @Published var results: [SemanticSearchResult] = []
    @Published var isSearching = false
    @Published var selectedIndex: Int = -1
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.3

    deinit {
        searchTask?.cancel()
    }

    var selectedResult: SemanticSearchResult? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    func search(query: String) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            selectedIndex = -1
            hasSearched = false
            return
        }

        isSearching = true

        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            let searchResults = await SemanticSearchManagerV2.shared.search(query: query, limit: 20)

            guard !Task.isCancelled else { return }

            results = searchResults
            selectedIndex = results.isEmpty ? -1 : 0
            isSearching = false
            hasSearched = true
        }
    }

    func selectNext() {
        guard !results.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    func selectPrevious() {
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func clear() {
        results = []
        selectedIndex = -1
        hasSearched = false
        searchTask?.cancel()
    }
}

// MARK: - Semantic Search Panel Content

struct SemanticSearchPanelContent: View {
    @ObservedObject var viewModel: SemanticSearchViewModel
    @ObservedObject var searchManager: SemanticSearchManagerV2
    let searchText: String
    let onSelect: (SemanticSearchResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if viewModel.results.isEmpty {
                        if searchText.isEmpty {
                            emptyStateNoQuery
                                .padding(.top, 30)
                        } else if viewModel.hasSearched && !viewModel.isSearching {
                            emptyStateNoResults
                                .padding(.top, 30)
                        } else if viewModel.isSearching {
                            searchingState
                                .padding(.top, 30)
                        }
                    } else {
                        ForEach(viewModel.results) { result in
                            SemanticResultRow(
                                result: result,
                                isSelected: viewModel.results.firstIndex(where: { $0.id == result.id }) == viewModel.selectedIndex,
                                onSelect: { onSelect(result) }
                            )
                            .id(result.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < viewModel.results.count {
                    let selectedId = viewModel.results[newIndex].id
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(selectedId, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyStateNoQuery: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24))
                .foregroundColor(.orange)

            VStack(spacing: 4) {
                Text("Semantic Search")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text("Search your history by meaning, not just keywords")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Index stats
            HStack(spacing: 16) {
                Label("\(searchManager.indexedCount) pages indexed", systemImage: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                if !searchManager.stats.available {
                    Label("Embeddings unavailable", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            .padding(.top, 8)
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

                Text("Try different words or a more general query")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var searchingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Searching...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Semantic Result Row

struct SemanticResultRow: View {
    let result: SemanticSearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    /// Cached domain extracted from URL (computed once at init)
    private let cachedDomain: String
    /// Cached display URL (computed once at init)
    private let cachedDisplayURL: String
    /// Cached domain color (computed once at init)
    private let cachedDomainColor: Color

    init(result: SemanticSearchResult, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.result = result
        self.isSelected = isSelected
        self.onSelect = onSelect

        // Pre-compute expensive string operations
        let domain: String
        if let url = URL(string: result.page.url), let host = url.host {
            domain = host.replacingOccurrences(of: "www.", with: "")
        } else {
            domain = ""
        }
        self.cachedDomain = domain

        // Pre-compute display URL
        var displayURL = result.page.url
        displayURL = displayURL.replacingOccurrences(of: "https://", with: "")
        displayURL = displayURL.replacingOccurrences(of: "http://", with: "")
        displayURL = displayURL.replacingOccurrences(of: "www.", with: "")
        if displayURL.count > 50 {
            displayURL = String(displayURL.prefix(47)) + "..."
        }
        self.cachedDisplayURL = displayURL

        // Pre-compute domain color
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
        ]
        let hash = domain.utf8.reduce(0) { $0 &+ Int($1) }
        self.cachedDomainColor = colors[abs(hash) % colors.count]
    }

    private var scorePercentage: Int {
        Int(result.score * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Favicon
            faviconView
                .frame(width: 28, height: 28)

            // Title, snippet, and URL
            VStack(alignment: .leading, spacing: 3) {
                Text(result.page.title.isEmpty ? cachedDomain : result.page.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !result.page.snippet.isEmpty {
                    Text(result.page.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(cachedDisplayURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            // Similarity score
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(scorePercentage)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(scoreColor)

                Text("match")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(scoreColor.opacity(0.1))
            )
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
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.orange.opacity(0.2)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color.clear
    }

    private var scoreColor: Color {
        if result.score > 0.8 {
            return .green
        } else if result.score > 0.5 {
            return .orange
        } else {
            return .secondary
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if !cachedDomain.isEmpty {
            let initial = String(cachedDomain.prefix(1)).uppercased()
            Text(initial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(cachedDomainColor)
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
}
