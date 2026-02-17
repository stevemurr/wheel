import SwiftUI

struct TabSidebar: View {
    @ObservedObject var state: BrowserState
    @ObservedObject private var settings = AppSettings.shared
    @State private var sidebarWidth: CGFloat = 220
    @State private var isResizing = false

    private let minWidth: CGFloat = 160
    private let maxWidth: CGFloat = 350
    private let collapsedWidth: CGFloat = 48

    /// Current effective width based on expanded/collapsed state
    private var effectiveWidth: CGFloat {
        settings.tabSidebarExpanded ? sidebarWidth : collapsedWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Header with Toggle and New Tab button
                HStack {
                    // Toggle button to expand/collapse sidebar
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            settings.tabSidebarExpanded.toggle()
                        }
                    }) {
                        Image(systemName: settings.tabSidebarExpanded ? "sidebar.left" : "sidebar.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(settings.tabSidebarExpanded ? "Collapse Sidebar" : "Expand Sidebar")

                    if settings.tabSidebarExpanded {
                        Text("Tabs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            state.addTab()
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New Tab")
                }
                .padding(.horizontal, settings.tabSidebarExpanded ? 12 : 8)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, settings.tabSidebarExpanded ? 8 : 4)

                // Scrollable tab list
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(state.tabs) { tab in
                            SidebarTabItem(
                                tab: tab,
                                isActive: tab.id == state.activeTabId,
                                isExpanded: settings.tabSidebarExpanded,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        state.selectTab(tab.id)
                                    }
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        state.closeTab(tab.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, settings.tabSidebarExpanded ? 8 : 4)
                    .padding(.vertical, 6)
                }

                Spacer(minLength: 0)
            }
            .frame(width: effectiveWidth)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            .clipped()

            // Resize handle (only when expanded)
            if settings.tabSidebarExpanded {
                ResizeHandle(
                    isResizing: $isResizing,
                    width: $sidebarWidth,
                    minWidth: minWidth,
                    maxWidth: maxWidth
                )
                .transition(.opacity)
            } else {
                // Simple divider when collapsed
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.tabSidebarExpanded)
    }
}

struct SidebarTabItem: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Expanded View (Icon + Title + Close Button)

    private var expandedView: some View {
        HStack(spacing: 8) {
            // Favicon or loading indicator
            faviconOrLoadingView
                .frame(width: 16, height: 16)

            // Title
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Close button (visible on hover)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .separatorColor).opacity(isHovering ? 0.5 : 0))
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Collapsed View (Icon Only)

    private var collapsedView: some View {
        VStack {
            faviconOrLoadingView
                .frame(width: 24, height: 24)
        }
        .frame(width: 36, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .help(tab.title) // Show title as tooltip when collapsed
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var faviconOrLoadingView: some View {
        ZStack {
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(isExpanded ? 0.5 : 0.7)
            } else {
                faviconView
            }
        }
    }

    private var backgroundFill: Color {
        if isActive {
            return Color(nsColor: .controlBackgroundColor)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        } else {
            return Color.clear
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let url = tab.url, let host = url.host {
            // Show first letter of domain as favicon placeholder
            let initial = String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased()
            Text(initial)
                .font(.system(size: isExpanded ? 10 : 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: isExpanded ? 16 : 24, height: isExpanded ? 16 : 24)
                .background(
                    RoundedRectangle(cornerRadius: isExpanded ? 3 : 5)
                        .fill(colorForDomain(host))
                )
        } else {
            Image(systemName: "globe")
                .font(.system(size: isExpanded ? 12 : 16))
                .foregroundColor(.secondary)
        }
    }

    // Generate a consistent color based on domain name
    private func colorForDomain(_ domain: String) -> Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
        ]
        let hash = domain.utf8.reduce(0) { $0 &+ Int($1) }
        return colors[abs(hash) % colors.count]
    }
}

struct ResizeHandle: View {
    @Binding var isResizing: Bool
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isResizing = true
                                let newWidth = width + value.translation.width
                                width = min(max(newWidth, minWidth), maxWidth)
                            }
                            .onEnded { _ in
                                isResizing = false
                            }
                    )
            )
    }
}

// Custom cursor modifier for resize handle
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Legacy Horizontal TabBar (kept for reference)
struct TabBar: View {
    @ObservedObject var state: BrowserState

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(state.tabs) { tab in
                        TabItem(
                            tab: tab,
                            isActive: tab.id == state.activeTabId,
                            onSelect: { state.selectTab(tab.id) },
                            onClose: { state.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Button(action: { state.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TabItem: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 120)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}
