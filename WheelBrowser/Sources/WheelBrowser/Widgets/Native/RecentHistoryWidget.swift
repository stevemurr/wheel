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
                emptyState
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No recent history")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryRowButton: View {
    let entry: HistoryEntry
    let compact: Bool

    @State private var isHovered = false

    private var domain: String {
        guard let url = URL(string: entry.url),
              let host = url.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
    }

    var body: some View {
        Button {
            if let url = URL(string: entry.url) {
                NotificationCenter.default.post(name: .openURL, object: url)
            }
        } label: {
            HStack(spacing: 10) {
                // Favicon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 28, height: 28)

                    Text(domain.prefix(1).uppercased())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

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
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(timeAgo)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 10))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
