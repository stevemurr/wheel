import SwiftUI

/// UI for displaying browsing history specific to the current workspace
struct WorkspaceHistoryView: View {
    @ObservedObject private var browsingHistory = BrowsingHistory.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared

    @State private var searchText = ""
    @State private var hoveredEntryID: UUID?

    private var currentWorkspace: Workspace? {
        workspaceManager.getCurrentWorkspace()
    }

    private var filteredEntries: [HistoryEntry] {
        guard let workspaceID = currentWorkspace?.id else {
            return []
        }
        return browsingHistory.search(query: searchText, workspaceID: workspaceID, limit: 50)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Browsing History", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if let workspace = currentWorkspace {
                    HStack(spacing: 4) {
                        Image(systemName: workspace.icon)
                            .font(.system(size: 10))
                            .foregroundColor(workspace.accentColor)
                        Text(workspace.name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // History list
            if currentWorkspace == nil {
                noWorkspaceView
            } else if filteredEntries.isEmpty {
                emptyStateView
            } else {
                historyListView
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Subviews

    private var noWorkspaceView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No workspace selected")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Select a workspace to view its history")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            Text(searchText.isEmpty ? "No history yet" : "No matching results")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "Pages you visit in this workspace will appear here" : "Try a different search term")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredEntries) { entry in
                    HistoryEntryRow(
                        entry: entry,
                        isHovered: hoveredEntryID == entry.id,
                        onOpen: {
                            openURL(entry.url)
                        },
                        onDelete: {
                            browsingHistory.removeEntry(entry)
                        }
                    )
                    .onHover { isHovered in
                        hoveredEntryID = isHovered ? entry.id : nil
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        // Post notification to open URL in browser
        NotificationCenter.default.post(name: .openURL, object: url)
    }
}

// MARK: - History Entry Row

struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let isHovered: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
    }

    private var domainString: String {
        guard let url = URL(string: entry.url),
              let host = url.host else {
            return entry.url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Favicon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 28, height: 28)

                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Title and URL
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(domainString)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time
            Text(formattedTime)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))

            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onOpen) {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Open")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red.opacity(0.8))
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let openURL = Notification.Name("openURL")
}

// MARK: - Preview

#Preview {
    WorkspaceHistoryView()
        .frame(width: 400, height: 300)
        .padding()
}
