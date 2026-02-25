import SwiftUI

/// Recent history widget showing recently visited pages
@MainActor
final class RecentHistoryWidget: Widget, ObservableObject {
    static let typeIdentifier = "recentHistory"
    static let displayName = "Recent History"
    static let iconName = "clock"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var allEntries: [HistoryEntry] = []

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large]
    }

    init() {
        Task {
            await refresh()
        }
    }

    @ViewBuilder
    func makeContent() -> some View {
        RecentHistoryWidgetView(entries: allEntries, size: currentSize)
    }

    func refresh() async {
        let history = BrowsingHistory.shared
        // Fetch enough entries for largest size
        allEntries = Array(history.entries.prefix(8))
    }
}

struct RecentHistoryWidgetView: View {
    let entries: [HistoryEntry]
    let size: WidgetSize

    private var visibleEntries: [HistoryEntry] {
        let limit = size == .large ? 8 : (size == .medium ? 5 : 3)
        return Array(entries.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if size != .small {
                Text("Recent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if visibleEntries.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No Recent History",
                    subtitle: "Browse the web to build history"
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleEntries) { entry in
                        HistoryRowButton(entry: entry, compact: size == .small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

struct HistoryRowButton: View {
    let entry: HistoryEntry
    let compact: Bool

    private var domain: String {
        entry.url.urlCleanDomain
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
    }

    var body: some View {
        Button {
            NotificationHelpers.postOpenURL(string: entry.url)
        } label: {
            HStack(spacing: 10) {
                FaviconPlaceholder(
                    domain: domain,
                    size: 28,
                    cornerRadius: 6,
                    style: .neutral
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !compact {
                        HStack(spacing: 4) {
                            Text(domain)
                                .foregroundStyle(.secondary)
                            Text("\u{2022}")
                                .foregroundStyle(.tertiary)
                            Text(timeAgo)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 10))
                    }
                }

                Spacer(minLength: 0)
            }
            .hoverableListItem()
        }
        .buttonStyle(.plain)
    }
}
