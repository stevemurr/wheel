import SwiftUI

// MARK: - Semantic Search Panel Content

struct SemanticSearchPanelContent: View {
    var viewModel: SemanticSearchViewModel
    var searchManager: SemanticSearchManagerV2
    let searchText: String
    let onSelect: (SemanticSearchResult) -> Void

    var body: some View {
        SelectableResultsPanel(
            items: viewModel.results,
            selectedIndex: viewModel.selectedIndex,
            emptyState: {
                Group {
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
                }
            },
            row: { index, result in
                SemanticResultRow(
                    result: result,
                    isSelected: index == viewModel.selectedIndex,
                    searchQuery: searchText,
                    onSelect: { onSelect(result) }
                )
            }
        )
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
                Label("\(searchManager.stats.pageCount) pages indexed", systemImage: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("\(searchManager.stats.chunkCount) chunks")
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
