import SwiftUI

struct RightClickPanel: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var screenshotManager = TabScreenshotManager.shared
    let onDismiss: () -> Void

    @State private var hoveredTabId: UUID?
    @State private var isCurrentPageSaved: Bool = false

    private let panelCornerRadius: CGFloat = 10
    private let panelPadding: CGFloat = 12

    var body: some View {
        VStack(spacing: 4) {
            // Navigation bar - compact
            navigationBar

            // Tab grid - horizontal flow
            if !browserState.tabs.isEmpty {
                Divider()
                    .padding(.horizontal, 2)

                tabGrid
            }

            Divider()
                .padding(.horizontal, 2)

            // Actions row
            actionsRow
        }
        .padding(panelPadding)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.98))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .fixedSize()
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: 6) {
            CompactNavButton(
                icon: "chevron.left",
                action: { browserState.activeTab?.goBack() },
                enabled: browserState.activeTab?.canGoBack ?? false
            )

            CompactNavButton(
                icon: "chevron.right",
                action: { browserState.activeTab?.goForward() },
                enabled: browserState.activeTab?.canGoForward ?? false
            )

            CompactNavButton(
                icon: "arrow.clockwise",
                action: { browserState.activeTab?.reload() },
                enabled: browserState.activeTab != nil
            )
        }
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: 6) {
            CompactActionButton(
                icon: isCurrentPageSaved ? "bookmark.fill" : "bookmark",
                label: isCurrentPageSaved ? "Saved" : "Save",
                color: .pink,
                action: toggleSaveCurrentPage
            )
        }
        .onAppear {
            checkIfCurrentPageIsSaved()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pageSaveStateChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let url = userInfo["url"] as? String,
               let isSaved = userInfo["isSaved"] as? Bool,
               url == browserState.activeTab?.url?.absoluteString {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCurrentPageSaved = isSaved
                }
            }
        }
    }

    private func toggleSaveCurrentPage() {
        guard let url = browserState.activeTab?.url else { return }

        Task {
            do {
                let database = try SearchDatabase()
                try await database.initialize()
                let isSaved = try await database.toggleSaved(url: url.absoluteString)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCurrentPageSaved = isSaved
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name("pageSaveStateChanged"),
                        object: nil,
                        userInfo: ["url": url.absoluteString, "isSaved": isSaved]
                    )
                }
            } catch {
                print("Failed to toggle save state: \(error)")
            }
        }
    }

    private func checkIfCurrentPageIsSaved() {
        guard let url = browserState.activeTab?.url else {
            isCurrentPageSaved = false
            return
        }

        Task {
            do {
                let database = try SearchDatabase()
                try await database.initialize()
                let saved = try await database.isSaved(url: url.absoluteString)
                await MainActor.run {
                    isCurrentPageSaved = saved
                }
            } catch {
                print("Failed to check save state: \(error)")
            }
        }
    }

    // MARK: - Tab Grid

    private var tabGrid: some View {
        let columns = min(browserState.tabs.count + 1, 4) // Max 4 per row for larger previews
        let gridColumns = Array(repeating: GridItem(.fixed(160), spacing: 12), count: columns)

        return LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(browserState.tabs) { tab in
                TabPreviewCard(
                    tab: tab,
                    screenshotManager: screenshotManager,
                    isActive: tab.id == browserState.activeTabId,
                    isHovered: tab.id == hoveredTabId,
                    canClose: browserState.tabs.count > 1,
                    onSelect: {
                        browserState.selectTab(tab.id)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onDismiss()
                        }
                    },
                    onClose: { browserState.closeTab(tab.id) }
                )
                .onHover { hovering in
                    hoveredTabId = hovering ? tab.id : nil
                }
            }

            // Add tab button
            LargeAddButton {
                browserState.addTab()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Compact Navigation Button

private struct CompactNavButton: View {
    let icon: String
    let action: () -> Void
    let enabled: Bool

    private let size: CGFloat = 26

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(enabled ? Color(nsColor: .labelColor) : Color(nsColor: .tertiaryLabelColor))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Compact Action Button

private struct CompactActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isHovered ? color : Color(nsColor: .labelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? color.opacity(0.15) : Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
