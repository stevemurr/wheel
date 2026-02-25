import SwiftUI

/// Reading list widget showing saved pages with AI-generated summaries
@MainActor
final class ReadingListWidget: Widget, ObservableObject {
    static let typeIdentifier = "readingList"
    static let displayName = "Reading List"
    static let iconName = "bookmark.fill"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var savedPages: [SavedPageRecord] = []
    @Published var isLoading = false
    @Published var wideItemCount: Int = 5

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large, .wide, .extraLarge]
    }

    init() {
        Task {
            await refresh()
        }
    }

    @ViewBuilder
    func makeContent() -> some View {
        ReadingListWidgetView(
            pages: savedPages,
            size: currentSize,
            isLoading: isLoading,
            wideItemCount: Binding(
                get: { self.wideItemCount },
                set: { self.wideItemCount = $0 }
            ),
            onRefresh: { Task { await self.refresh() } }
        )
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let database = try SearchDatabase()
            try await database.initialize()
            // Fetch more items for expanded mode scrolling
            let limit = (currentSize == .wide || currentSize == .extraLarge) ? max(wideItemCount, 20) : 8
            savedPages = try await database.getSavedPages(limit: limit)

            // Trigger backfill for pages without summaries
            Task.detached {
                await SummaryGenerator.shared.backfillSummaries()
            }
        } catch {
            print("[ReadingListWidget] Failed to load saved pages: \(error)")
            savedPages = []
        }
    }

    func encodeConfiguration() -> [String: Any] {
        ["wideItemCount": wideItemCount]
    }

    func decodeConfiguration(_ data: [String: Any]) {
        if let count = data["wideItemCount"] as? Int {
            wideItemCount = count
        }
    }
}

struct ReadingListWidgetView: View {
    let pages: [SavedPageRecord]
    let size: WidgetSize
    let isLoading: Bool
    @Binding var wideItemCount: Int
    let onRefresh: () -> Void

    @State private var isConfiguring = false
    @State private var isRegeneratingAll = false
    @State private var regenerationProgress: (current: Int, total: Int)?

    private var visiblePages: [SavedPageRecord] {
        let limit: Int
        switch size {
        case .large: limit = 8
        case .medium: limit = 5
        case .wide, .extraLarge: limit = wideItemCount
        default: limit = 3
        }
        return Array(pages.prefix(limit))
    }

    private var isExpandedMode: Bool {
        size == .wide || size == .extraLarge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            if size != .small {
                header
            }

            // Content
            if visiblePages.isEmpty {
                emptyState
            } else if isExpandedMode {
                wideContent
            } else {
                standardContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Text("Reading List")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if isExpandedMode {
                Text("\(visiblePages.count) of \(pages.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isExpandedMode {
                // Item count controls
                HStack(spacing: 4) {
                    Button {
                        if wideItemCount > 1 {
                            wideItemCount -= 1
                            onRefresh()
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .disabled(wideItemCount <= 1)

                    Text("\(wideItemCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 20)

                    Button {
                        if wideItemCount < 20 {
                            wideItemCount += 1
                            onRefresh()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .disabled(wideItemCount >= 20)
                }
            }

            if isLoading || isRegeneratingAll {
                if let progress = regenerationProgress {
                    Text("\(progress.current)/\(progress.total)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Menu {
                    Button {
                        regenerateAllSummaries()
                    } label: {
                        Label("Regenerate All Summaries", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20, height: 20)
            }
        }
    }

    private var standardContent: some View {
        VStack(spacing: 2) {
            ForEach(visiblePages) { page in
                ReadingListRowButton(
                    page: page,
                    compact: size == .small,
                    expanded: false,
                    onRegenerateSummary: regenerateSummary
                )
            }
        }
    }

    private var wideContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 8) {
                ForEach(visiblePages) { page in
                    ReadingListRowButton(
                        page: page,
                        compact: false,
                        expanded: true,
                        onRegenerateSummary: regenerateSummary
                    )
                }
            }
        }
    }

    private func regenerateSummary(for url: URL) {
        Task {
            _ = await SummaryGenerator.shared.regenerateSummary(for: url)
            onRefresh()
        }
    }

    private func regenerateAllSummaries() {
        isRegeneratingAll = true
        regenerationProgress = nil

        Task {
            await SummaryGenerator.shared.regenerateAllSummaries { current, total in
                Task { @MainActor in
                    regenerationProgress = (current, total)
                }
            }
            await MainActor.run {
                isRegeneratingAll = false
                regenerationProgress = nil
                onRefresh()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No saved pages")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Save pages to read later")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReadingListRowButton: View {
    let page: SavedPageRecord
    let compact: Bool
    var expanded: Bool = false
    var onRegenerateSummary: ((URL) -> Void)?

    @State private var isHovered = false
    @State private var isRegenerating = false

    private var domain: String {
        page.domain.replacingOccurrences(of: "www.", with: "")
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: page.savedAt, relativeTo: Date())
    }

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openURL, object: page.url)
        } label: {
            HStack(spacing: 10) {
                // Favicon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: expanded ? 32 : 28, height: expanded ? 32 : 28)

                    Text(domain.prefix(1).uppercased())
                        .font(.system(size: expanded ? 14 : 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: expanded ? 4 : 2) {
                    HStack(spacing: 8) {
                        Text(page.displayTitle)
                            .font(.system(size: expanded ? 13 : (compact ? 11 : 12), weight: expanded ? .medium : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if expanded {
                            Spacer()

                            HStack(spacing: 4) {
                                Text(domain)
                                    .foregroundStyle(.tertiary)
                                Text("\u{2022}")
                                    .foregroundStyle(.quaternary)
                                Text(timeAgo)
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 10))
                        }
                    }

                    if !compact {
                        // Summary or domain + time
                        if let summary = page.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: expanded ? 11 : 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(expanded ? nil : 2)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: expanded)
                        } else if !expanded {
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
                }

                if !expanded {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, expanded ? 12 : 8)
            .padding(.vertical, expanded ? 10 : 6)
            .background {
                RoundedRectangle(cornerRadius: expanded ? 10 : 8)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                isRegenerating = true
                onRegenerateSummary?(page.url)
            } label: {
                Label("Regenerate Summary", systemImage: "arrow.clockwise")
            }
        }
        .overlay(alignment: .trailing) {
            if isRegenerating {
                ProgressView()
                    .scaleEffect(0.5)
                    .padding(.trailing, 8)
            }
        }
        .onChange(of: page.summary) { _, _ in
            isRegenerating = false
        }
    }
}
