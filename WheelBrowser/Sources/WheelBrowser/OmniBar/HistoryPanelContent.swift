import SwiftUI

// MARK: - History Panel using OmniPanel

struct HistoryPanelContent: View {
    @ObservedObject var viewModel: SuggestionsViewModel
    let searchText: String
    let onSelect: (Suggestion) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if viewModel.suggestions.isEmpty {
                        if searchText.isEmpty {
                            // No history at all
                            OmniPanelEmptyState(
                                icon: "clock",
                                title: "No browsing history",
                                subtitle: "Pages you visit will appear here"
                            )
                            .padding(.top, 30)
                        } else {
                            // No search results
                            OmniPanelEmptyState(
                                icon: "magnifyingglass",
                                title: "No matches found",
                                subtitle: "Try a different search term"
                            )
                            .padding(.top, 30)
                        }
                    } else {
                        // Show suggestions (either search results or recent history)
                        ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionRow(
                                suggestion: suggestion,
                                isSelected: index == viewModel.selectedIndex,
                                onSelect: { onSelect(suggestion) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < viewModel.suggestions.count {
                    let selectedId = viewModel.suggestions[newIndex].id
                    withAnimation(AppAnimation.quickOut) {
                        proxy.scrollTo(selectedId, anchor: .center)
                    }
                }
            }
        }
    }

    var subtitle: String {
        if !searchText.isEmpty {
            return "\(viewModel.suggestions.count) results"
        }
        return "Recent"
    }
}
