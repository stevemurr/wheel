import SwiftUI

struct RightClickPanel: View {
    @ObservedObject var browserState: BrowserState
    let onDismiss: () -> Void

    @State private var hoveredTabId: UUID?

    private let panelCornerRadius: CGFloat = 10
    private let panelPadding: CGFloat = 6

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

    // MARK: - Tab Grid

    private var tabGrid: some View {
        let columns = min(browserState.tabs.count + 1, 5) // Max 5 per row
        let gridColumns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: columns)

        return LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(browserState.tabs) { tab in
                CompactTabButton(
                    tab: tab,
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
            CompactAddButton {
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

// MARK: - Compact Tab Button

private struct CompactTabButton: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isHovered: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var showClose = false

    private let size: CGFloat = 32
    private let cornerRadius: CGFloat = 7

    private var background: Color {
        if isActive {
            return Color(nsColor: .controlAccentColor)
        } else {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
    }

    private var textColor: Color {
        isActive ? .white : Color(nsColor: .secondaryLabelColor)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(background)
                .frame(width: size, height: size)

            // Agent indicator
            if tab.hasActiveAgent {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.green, lineWidth: 1.5)
                    .frame(width: size, height: size)
            }

            // Favicon or initial
            faviconContent

            // Close button on hover
            if showClose && canClose && !tab.hasActiveAgent {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(textColor.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: size / 2 - 5, y: -size / 2 + 5)
            }
        }
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onTapGesture(perform: onSelect)
        .onHover { showClose = $0 }
        .help(tab.title)
    }

    private var faviconContent: some View {
        Group {
            if let url = tab.url, let host = url.host {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textColor)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
            }
        }
    }
}

// MARK: - Compact Add Button

private struct CompactAddButton: View {
    let action: () -> Void

    private let size: CGFloat = 32
    private let cornerRadius: CGFloat = 7

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                )
        }
        .buttonStyle(.plain)
    }
}
