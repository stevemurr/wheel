import SwiftUI

/// Hero search bar widget for the new tab page
@MainActor
final class SearchWidget: Widget, ObservableObject {
    static let typeIdentifier = "search"
    static let displayName = "Search"
    static let iconName = "magnifyingglass"

    let id = UUID()
    @Published var currentSize: WidgetSize = .wide

    var supportedSizes: [WidgetSize] {
        [.medium, .wide]
    }

    @ViewBuilder
    func makeContent() -> some View {
        SearchWidgetView()
    }

    func refresh() async {
        // No data to refresh
    }
}

struct SearchWidgetView: View {
    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search or enter URL", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)
                .onSubmit {
                    performSearch()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.5) : Color.clear,
                    lineWidth: 2
                )
        }
        .padding(8)
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        // Post notification to load URL in active tab
        if let url = URL(string: searchText), url.scheme != nil {
            NotificationCenter.default.post(name: .openURL, object: url)
        } else {
            // Treat as search query
            let encoded = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchText
            if let searchURL = URL(string: "https://duckduckgo.com/?q=\(encoded)") {
                NotificationCenter.default.post(name: .openURL, object: searchURL)
            }
        }

        searchText = ""
    }
}
