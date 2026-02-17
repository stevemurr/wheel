import SwiftUI

/// UI for displaying and managing workspaces in the top drawer
struct WorkspacesView: View {
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @State private var isCreatingWorkspace = false
    @State private var editingWorkspace: Workspace?
    @State private var showingDeleteConfirmation: Workspace?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Workspaces")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { isCreatingWorkspace = true }) {
                    Label("New Workspace", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Workspace grid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(workspaceManager.workspaces) { workspace in
                        WorkspaceCard(
                            workspace: workspace,
                            isSelected: workspace.id == workspaceManager.currentWorkspaceID,
                            tabCount: workspaceManager.tabCount(for: workspace.id),
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    workspaceManager.switchToWorkspace(workspace.id)
                                }
                            },
                            onEdit: {
                                editingWorkspace = workspace
                            },
                            onDelete: {
                                showingDeleteConfirmation = workspace
                            }
                        )
                    }

                    // Add workspace button card
                    AddWorkspaceCard {
                        isCreatingWorkspace = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
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
}

// MARK: - Workspace Card

struct WorkspaceCard: View {
    let workspace: Workspace
    let isSelected: Bool
    let tabCount: Int
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon and name row
            HStack(spacing: 8) {
                Image(systemName: workspace.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(workspace.accentColor)
                    .frame(width: 24, height: 24)

                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Tab count
            HStack {
                Text("\(tabCount) tab\(tabCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding(12)
        .frame(width: 160, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color(nsColor: .windowBackgroundColor).opacity(0.6)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? workspace.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.1 : 0.05), radius: isSelected ? 4 : 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("Switch to Workspace", systemImage: "arrow.right.circle")
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

// MARK: - Add Workspace Card

struct AddWorkspaceCard: View {
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary)

            Text("New")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(width: 80, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(isHovering ? 0.8 : 0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Workspace Editor Sheet

struct WorkspaceEditorSheet: View {
    enum Mode {
        case create
        case edit(Workspace)

        var title: String {
            switch self {
            case .create: return "New Workspace"
            case .edit: return "Edit Workspace"
            }
        }

        var saveButtonTitle: String {
            switch self {
            case .create: return "Create"
            case .edit: return "Save"
            }
        }
    }

    let mode: Mode
    let onSave: (String, String, String, UUID?) -> Void
    let onCancel: () -> Void

    @ObservedObject private var agentStudioManager = AgentStudioManager.shared

    @State private var name: String = ""
    @State private var selectedIcon: String = "folder"
    @State private var selectedColor: String = "#007AFF"
    @State private var selectedAgentID: UUID?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(mode.saveButtonTitle) {
                    onSave(
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                        selectedIcon,
                        selectedColor,
                        selectedAgentID
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(isValid ? .accentColor : .secondary)
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview
                    HStack {
                        Spacer()
                        WorkspacePreview(name: name, icon: selectedIcon, color: selectedColor)
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("Workspace name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
                            ForEach(Workspace.availableIcons, id: \.self) { icon in
                                IconPickerItem(
                                    icon: icon,
                                    isSelected: icon == selectedIcon,
                                    color: selectedColor
                                ) {
                                    selectedIcon = icon
                                }
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(Workspace.availableColors, id: \.self) { color in
                                ColorPickerItem(
                                    color: color,
                                    isSelected: color == selectedColor
                                ) {
                                    selectedColor = color
                                }
                            }
                        }
                    }

                    // Agent picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default Agent")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "None" option
                                AgentPickerItem(
                                    name: "None",
                                    icon: "minus.circle",
                                    isSelected: selectedAgentID == nil,
                                    color: selectedColor
                                ) {
                                    selectedAgentID = nil
                                }

                                ForEach(agentStudioManager.agents) { agent in
                                    AgentPickerItem(
                                        name: agent.name,
                                        icon: agent.icon,
                                        isSelected: selectedAgentID == agent.id,
                                        color: selectedColor
                                    ) {
                                        selectedAgentID = agent.id
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 360, height: 500)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if case .edit(let workspace) = mode {
                name = workspace.name
                selectedIcon = workspace.icon
                selectedColor = workspace.color
                selectedAgentID = workspace.defaultAgentID
            }
        }
    }
}

// MARK: - Agent Picker Item

struct AgentPickerItem: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let color: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? (Color(hex: color) ?? .blue) : .secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected
                                ? (Color(hex: color) ?? .blue).opacity(0.15)
                                : Color(nsColor: .controlBackgroundColor)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? (Color(hex: color) ?? .blue).opacity(0.5) : Color.clear,
                                lineWidth: 1
                            )
                    )

                Text(name)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workspace Preview

struct WorkspacePreview: View {
    let name: String
    let icon: String
    let color: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(Color(hex: color) ?? .blue)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill((Color(hex: color) ?? .blue).opacity(0.15))
                )

            Text(name.isEmpty ? "Workspace" : name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Icon Picker Item

struct IconPickerItem: View {
    let icon: String
    let isSelected: Bool
    let color: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? (Color(hex: color) ?? .blue) : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected
                            ? (Color(hex: color) ?? .blue).opacity(0.15)
                            : Color(nsColor: .controlBackgroundColor)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? (Color(hex: color) ?? .blue).opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Picker Item

struct ColorPickerItem: View {
    let color: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(Color(hex: color) ?? .blue)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                        .padding(2)
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? (Color(hex: color) ?? .blue) : Color.clear,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    WorkspacesView()
        .frame(width: 600, height: 120)
        .background(Color(nsColor: .windowBackgroundColor))
}
