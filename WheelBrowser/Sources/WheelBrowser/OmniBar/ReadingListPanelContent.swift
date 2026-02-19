import SwiftUI

/// Panel content for the reading list mode in OmniBar
struct ReadingListPanelContent: View {
    @ObservedObject var viewModel: ReadingListViewModel
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
                    withAnimation(.easeOut(duration: 0.1)) {
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
        item.url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
    }

    private var savedDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.savedAt, relativeTo: Date())
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
            withAnimation(.easeInOut(duration: 0.1)) {
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
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
        ]
        let hash = domain.utf8.reduce(0) { $0 &+ Int($1) }
        return colors[abs(hash) % colors.count]
    }
}
