import SwiftUI

struct TabSidebar: View {
    @ObservedObject var state: BrowserState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @State private var sidebarWidth: CGFloat = 220
    @State private var isResizing = false

    /// Callback when a workspace is selected - used to trigger tab switching
    var onWorkspaceSelected: ((UUID) -> Void)?

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
                // Workspace selector at the top
                WorkspaceFanoutSelector(
                    isExpanded: settings.tabSidebarExpanded,
                    onWorkspaceSelected: { workspaceId in
                        onWorkspaceSelected?(workspaceId)
                    }
                )
                .padding(.horizontal, settings.tabSidebarExpanded ? 8 : 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Divider between workspace and tabs
                Divider()
                    .padding(.horizontal, settings.tabSidebarExpanded ? 8 : 4)

                // Header with Tabs label
                HStack {
                    if settings.tabSidebarExpanded {
                        Text("Tabs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    Spacer()
                }
                .padding(.horizontal, settings.tabSidebarExpanded ? 12 : 8)
                .padding(.vertical, 8)

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

// MARK: - Workspace Fanout Selector

/// A workspace selector that shows only the active workspace icon,
/// and fans out horizontally on hover to show all workspaces
struct WorkspaceFanoutSelector: View {
    let isExpanded: Bool
    var onWorkspaceSelected: ((UUID) -> Void)?

    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var agentStudioManager = AgentStudioManager.shared
    @State private var isHovering = false
    @State private var isFannedOut = false
    @State private var isCreatingWorkspace = false
    @State private var editingWorkspace: Workspace?
    @State private var showingDeleteConfirmation: Workspace?

    private let iconSize: CGFloat = 32
    private let fanoutSpacing: CGFloat = 6

    /// The current workspace
    private var currentWorkspace: Workspace? {
        workspaceManager.getCurrentWorkspace()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main container that expands on hover
            HStack(spacing: fanoutSpacing) {
                // Active workspace icon (always visible)
                if let workspace = currentWorkspace {
                    ActiveWorkspaceIcon(
                        workspace: workspace,
                        iconSize: iconSize,
                        isExpanded: isExpanded,
                        showLabel: isExpanded && !isFannedOut
                    )
                    .onTapGesture {
                        // Toggle fan out on tap when collapsed
                        if !isExpanded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isFannedOut.toggle()
                            }
                        }
                    }
                    .contextMenu {
                        Button(action: { editingWorkspace = workspace }) {
                            Label("Edit Workspace...", systemImage: "pencil")
                        }

                        if workspaceManager.workspaces.count > 1 {
                            Divider()
                            Button(role: .destructive) {
                                showingDeleteConfirmation = workspace
                            } label: {
                                Label("Delete Workspace", systemImage: "trash")
                            }
                        }
                    }
                }

                // Fanned out workspace icons (visible on hover)
                if isFannedOut {
                    ForEach(workspaceManager.workspaces) { workspace in
                        if workspace.id != workspaceManager.currentWorkspaceID {
                            FanoutWorkspaceIcon(
                                workspace: workspace,
                                iconSize: iconSize,
                                tabCount: workspaceManager.tabCount(for: workspace.id),
                                onSelect: {
                                    selectWorkspace(workspace)
                                },
                                onEdit: {
                                    editingWorkspace = workspace
                                },
                                onDelete: {
                                    showingDeleteConfirmation = workspace
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            ))
                        }
                    }

                    // Add workspace button
                    FanoutAddButton(iconSize: iconSize) {
                        isCreatingWorkspace = true
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFannedOut ? Color(nsColor: .controlBackgroundColor).opacity(0.8) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isHovering = hovering
                    if hovering {
                        isFannedOut = true
                    }
                }

                // Delay hiding the fanout when mouse leaves
                if !hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if !isHovering {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                isFannedOut = false
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isCreatingWorkspace) {
            WorkspaceEditorSheet(
                mode: .create,
                onSave: { name, icon, color, agentID in
                    let newWorkspace = workspaceManager.createWorkspace(name: name, icon: icon, color: color, defaultAgentID: agentID)
                    isCreatingWorkspace = false
                    // Auto-switch to the newly created workspace
                    selectWorkspace(newWorkspace)
                },
                onCancel: {
                    isCreatingWorkspace = false
                }
            )
        }
        .sheet(item: $editingWorkspace) { workspace in
            WorkspaceEditorSheet(
                mode: .edit(workspace),
                onSave: { name, icon, color, agentID in
                    workspaceManager.updateWorkspace(
                        id: workspace.id,
                        name: name,
                        icon: icon,
                        color: color,
                        defaultAgentID: agentID
                    )
                    editingWorkspace = nil
                },
                onCancel: {
                    editingWorkspace = nil
                }
            )
        }
        .alert(
            "Delete Workspace?",
            isPresented: Binding(
                get: { showingDeleteConfirmation != nil },
                set: { if !$0 { showingDeleteConfirmation = nil } }
            ),
            presenting: showingDeleteConfirmation
        ) { workspace in
            Button("Delete", role: .destructive) {
                workspaceManager.deleteWorkspace(workspace.id)
                showingDeleteConfirmation = nil
            }
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmation = nil
            }
        } message: { workspace in
            Text("Are you sure you want to delete \"\(workspace.name)\"? This cannot be undone.")
        }
    }

    private func selectWorkspace(_ workspace: Workspace) {
        withAnimation(.easeInOut(duration: 0.2)) {
            workspaceManager.switchToWorkspace(workspace.id)

            // Switch to the workspace's agent if it has one
            if let agentID = workspace.defaultAgentID {
                agentStudioManager.setActiveAgent(id: agentID)
            }

            // Notify parent to switch tabs
            onWorkspaceSelected?(workspace.id)

            // Close the fanout
            isFannedOut = false
        }
    }
}

// MARK: - Active Workspace Icon

/// The main workspace icon that is always visible
struct ActiveWorkspaceIcon: View {
    let workspace: Workspace
    let iconSize: CGFloat
    let isExpanded: Bool
    let showLabel: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                // Background circle with accent color
                Circle()
                    .fill(workspace.accentColor.opacity(0.15))
                    .frame(width: iconSize, height: iconSize)

                // Icon
                Image(systemName: workspace.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(workspace.accentColor)

                // Selection ring
                Circle()
                    .stroke(workspace.accentColor, lineWidth: 2)
                    .frame(width: iconSize + 4, height: iconSize + 4)
            }
            .frame(width: iconSize + 8, height: iconSize + 8)

            // Workspace name (when expanded and not fanned out)
            if showLabel {
                Text(workspace.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("Click or hover to switch workspaces")
    }
}

// MARK: - Fanout Workspace Icon

/// A workspace icon shown in the fanout
struct FanoutWorkspaceIcon: View {
    let workspace: Workspace
    let iconSize: CGFloat
    let tabCount: Int
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Background circle
                Circle()
                    .fill(isHovering ? workspace.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                    .frame(width: iconSize, height: iconSize)

                // Icon
                Image(systemName: workspace.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovering ? workspace.accentColor : .secondary)

                // Tab count badge
                if tabCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(tabCount)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(workspace.accentColor)
                                )
                        }
                        Spacer()
                    }
                    .frame(width: iconSize + 6, height: iconSize + 6)
                }
            }
            .frame(width: iconSize + 4, height: iconSize + 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .help(workspace.name)
        .contextMenu {
            Button(action: onSelect) {
                Label("Switch to \(workspace.name)", systemImage: "arrow.right.circle")
            }

            Divider()

            Button(action: onEdit) {
                Label("Edit...", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Fanout Add Button

/// The add button shown at the end of the fanout
struct FanoutAddButton: View {
    let iconSize: CGFloat
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .frame(width: iconSize, height: iconSize)

                Circle()
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(isHovering ? 0.8 : 0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                    .frame(width: iconSize, height: iconSize)

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: iconSize + 4, height: iconSize + 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .help("Create new workspace")
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
