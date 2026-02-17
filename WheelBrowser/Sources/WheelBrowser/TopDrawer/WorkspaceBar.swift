import SwiftUI

/// A horizontal bar of workspace icons displayed at the top of the browser
struct WorkspaceBar: View {
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var agentStudioManager = AgentStudioManager.shared
    @State private var isCreatingWorkspace = false
    @State private var editingWorkspace: Workspace?
    @State private var showingDeleteConfirmation: Workspace?

    /// Callback when a workspace is selected - used to trigger tab switching
    var onWorkspaceSelected: ((UUID) -> Void)?

    private let barHeight: CGFloat = 44
    private let iconSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            // Workspace icons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workspaceManager.workspaces) { workspace in
                        WorkspaceIcon(
                            workspace: workspace,
                            isSelected: workspace.id == workspaceManager.currentWorkspaceID,
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
                    }

                    // Add workspace button
                    AddWorkspaceButton {
                        isCreatingWorkspace = true
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(height: barHeight)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1),
            alignment: .bottom
        )
        .sheet(isPresented: $isCreatingWorkspace) {
            WorkspaceEditorSheet(
                mode: .create,
                onSave: { name, icon, color, agentID in
                    workspaceManager.createWorkspace(name: name, icon: icon, color: color, defaultAgentID: agentID)
                    isCreatingWorkspace = false
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
        }
    }
}

// MARK: - Workspace Icon

struct WorkspaceIcon: View {
    let workspace: Workspace
    let isSelected: Bool
    let tabCount: Int
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private let iconSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Background circle
                Circle()
                    .fill(backgroundFill)
                    .frame(width: iconSize, height: iconSize)

                // Icon
                Image(systemName: workspace.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? workspace.accentColor : .secondary)

                // Selection indicator ring
                if isSelected {
                    Circle()
                        .stroke(workspace.accentColor, lineWidth: 2)
                        .frame(width: iconSize + 4, height: iconSize + 4)
                }

                // Tab count badge (only when there are tabs)
                if tabCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(tabCount)")
                                .font(.system(size: 9, weight: .semibold))
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
                    .frame(width: iconSize + 8, height: iconSize + 8)
                }
            }
            .frame(width: iconSize + 8, height: iconSize + 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
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

    private var backgroundFill: Color {
        if isSelected {
            return workspace.accentColor.opacity(0.15)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Add Workspace Button

struct AddWorkspaceButton: View {
    let onTap: () -> Void

    @State private var isHovering = false

    private let iconSize: CGFloat = 32

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
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("Create new workspace")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        WorkspaceBar()

        Rectangle()
            .fill(Color.blue.opacity(0.2))
            .frame(height: 400)
    }
    .frame(width: 600)
}
