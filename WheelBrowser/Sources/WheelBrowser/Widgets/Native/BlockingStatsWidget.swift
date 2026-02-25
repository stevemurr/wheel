import SwiftUI

/// Blocking statistics widget displaying content blocking metrics
@MainActor
final class BlockingStatsWidget: Widget, ObservableObject {
    static let typeIdentifier = "blockingStats"
    static let displayName = "Blocking Stats"
    static let iconName = "shield.fill"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var stats: BlockingStats.Summary?

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
        BlockingStatsWidgetView(stats: stats, size: currentSize)
    }

    func refresh() async {
        stats = BlockingStats.shared.summary
    }
}

struct BlockingStatsWidgetView: View {
    let stats: BlockingStats.Summary?
    let size: WidgetSize

    var body: some View {
        Group {
            switch size {
            case .small:
                smallView
            case .medium:
                mediumView
            case .large, .wide, .extraLarge:
                largeView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .small ? .center : .topLeading)
    }

    // MARK: - Small View (Total only)

    private var smallView: some View {
        VStack(spacing: 4) {
            Image(systemName: "shield.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)

            Text(stats?.totalBlocked ?? "0")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text("Blocked")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Medium View (Total + Session + Pages)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)

                Text("Content Blocked")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack(spacing: 16) {
                StatItem(
                    value: stats?.totalBlocked ?? "0",
                    label: "Total",
                    icon: "sum"
                )

                StatItem(
                    value: stats?.sessionBlocked ?? "0",
                    label: "Session",
                    icon: "clock"
                )

                StatItem(
                    value: "\(stats?.pagesProtected ?? 0)",
                    label: "Pages",
                    icon: "doc"
                )
            }
        }
    }

    // MARK: - Large View (Full breakdown with categories)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)

                Text("Content Blocked")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let days = stats?.daysSinceStart, days > 0 {
                    Text("\(days) days")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            // Primary stats
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats?.totalBlocked ?? "0")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Total Blocked")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(stats?.averagePerDay ?? "0")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Per Day")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Category breakdown
            VStack(spacing: 8) {
                ForEach(BlockingCategory.allCases, id: \.self) { category in
                    CategoryRow(category: category)
                }
            }

            // Bottom stats
            HStack(spacing: 16) {
                Label {
                    Text("\(stats?.sessionBlocked ?? "0") this session")
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)

                Label {
                    Text("\(stats?.pagesProtected ?? 0) pages protected")
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Supporting Views

private struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct CategoryRow: View {
    let category: BlockingCategory

    private var count: Int {
        BlockingStats.shared.blockedByCategory[category] ?? 0
    }

    private var formattedCount: String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private var percentage: Double {
        let total = BlockingStats.shared.totalBlocked
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 12))
                .frame(width: 20)
                .foregroundStyle(colorForCategory)

            Text(category.displayName)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedCount)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 4)

                    Capsule()
                        .fill(colorForCategory)
                        .frame(width: geometry.size.width * percentage, height: 4)
                }
            }
            .frame(width: 50, height: 4)
        }
    }

    private var colorForCategory: Color {
        switch category {
        case .ads:
            return .red
        case .trackers:
            return .orange
        case .socialWidgets:
            return .blue
        case .annoyances:
            return .purple
        }
    }
}

#Preview("Small") {
    BlockingStatsWidgetView(
        stats: BlockingStats.Summary(
            totalBlocked: "1.2K",
            sessionBlocked: "156",
            pagesProtected: 42,
            topCategory: .trackers,
            topCategoryCount: "580",
            daysSinceStart: 14,
            averagePerDay: "85"
        ),
        size: .small
    )
    .frame(width: 150, height: 150)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Medium") {
    BlockingStatsWidgetView(
        stats: BlockingStats.Summary(
            totalBlocked: "1.2K",
            sessionBlocked: "156",
            pagesProtected: 42,
            topCategory: .trackers,
            topCategoryCount: "580",
            daysSinceStart: 14,
            averagePerDay: "85"
        ),
        size: .medium
    )
    .frame(width: 300, height: 150)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Large") {
    BlockingStatsWidgetView(
        stats: BlockingStats.Summary(
            totalBlocked: "12.5K",
            sessionBlocked: "456",
            pagesProtected: 342,
            topCategory: .trackers,
            topCategoryCount: "5.8K",
            daysSinceStart: 45,
            averagePerDay: "278"
        ),
        size: .large
    )
    .frame(width: 300, height: 300)
    .background(Color(nsColor: .windowBackgroundColor))
}
