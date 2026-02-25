import SwiftUI

/// Quick links widget showing frequently visited sites
@MainActor
final class QuickLinksWidget: Widget, ObservableObject {
    static let typeIdentifier = "quickLinks"
    static let displayName = "Quick Links"
    static let iconName = "square.grid.2x2"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var topSites: [QuickLink] = []

    struct QuickLink: Identifiable {
        let id = UUID()
        let title: String
        let url: URL
        let domain: String
    }

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
        QuickLinksWidgetView(topSites: topSites, size: currentSize)
    }

    func refresh() async {
        // Get top sites from browsing history
        let history = BrowsingHistory.shared
        let entries = history.entries

        // Count visits per domain
        var domainCounts: [String: (count: Int, entry: HistoryEntry)] = [:]
        for entry in entries {
            guard let url = URL(string: entry.url) else { continue }
            let domain = url.cleanDomain
            guard !domain.isEmpty else { continue }

            if let existing = domainCounts[domain] {
                domainCounts[domain] = (existing.count + 1, existing.entry)
            } else {
                domainCounts[domain] = (1, entry)
            }
        }

        // Sort by count and take top 8
        let sorted = domainCounts.sorted { $0.value.count > $1.value.count }
        let top = sorted.prefix(8)

        topSites = top.compactMap { (domain, value) -> QuickLink? in
            guard let url = URL(string: value.entry.url) else { return nil }
            let title = value.entry.title.isEmpty ? domain : value.entry.title
            // Truncate title if too long
            let displayTitle = title.count > 20 ? String(title.prefix(17)) + "..." : title
            return QuickLink(title: displayTitle, url: url, domain: domain)
        }
    }
}

struct QuickLinksWidgetView: View {
    let topSites: [QuickLinksWidget.QuickLink]
    let size: WidgetSize

    private var columns: [GridItem] {
        let count = size == .small ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var visibleSites: [QuickLinksWidget.QuickLink] {
        let limit = size == .small ? 4 : (size == .large ? 8 : 4)
        return Array(topSites.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if size != .small {
                Text("Quick Links")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if visibleSites.isEmpty {
                EmptyStateView(
                    icon: "globe",
                    title: "No Recent Sites",
                    subtitle: "Browse the web to see quick links"
                )
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleSites) { site in
                        QuickLinkButton(site: site, compact: size == .small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

struct QuickLinkButton: View {
    let site: QuickLinksWidget.QuickLink
    let compact: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationHelpers.postOpenURL(site.url)
        } label: {
            VStack(spacing: 6) {
                FaviconPlaceholder(
                    domain: site.domain,
                    size: compact ? 36 : 44,
                    cornerRadius: 8,
                    style: .accent
                )

                if !compact {
                    Text(site.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
