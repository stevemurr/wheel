import SwiftUI

/// UI for the Agent Studio section of the top drawer
struct AgentStudioView: View {
    @ObservedObject var manager: AgentStudioManager
    /// Binding to notify parent when a sheet is presented (keeps drawer visible)
    @Binding var isSheetPresented: Bool

    @State private var showingEditor = false
    @State private var editingAgent: AgentConfig?
    @State private var hoveredAgentID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Agent Studio", systemImage: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    editingAgent = nil
                    showingEditor = true
                }) {
                    Label("Create Agent", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Agent list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(manager.agents) { agent in
                        AgentCard(
                            agent: agent,
                            isActive: manager.activeAgentID == agent.id,
                            isHovered: hoveredAgentID == agent.id,
                            onSelect: {
                                manager.setActiveAgent(id: agent.id)
                            },
                            onEdit: {
                                editingAgent = agent
                                showingEditor = true
                            },
                            onDuplicate: {
                                manager.duplicateAgent(id: agent.id)
                            },
                            onDelete: {
                                manager.deleteAgent(id: agent.id)
                            }
                        )
                        .onHover { isHovered in
                            hoveredAgentID = isHovered ? agent.id : nil
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingEditor) {
            AgentEditorSheet(
                manager: manager,
                existingAgent: editingAgent
            )
        }
        .onChange(of: showingEditor) { _, newValue in
            // Sync sheet presentation state to parent
            isSheetPresented = newValue
        }
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    let agent: AgentConfig
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .frame(width: 36, height: 36)

                Image(systemName: agent.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? .white : .secondary)
            }

            // Name and skills
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if agent.isDefault {
                        Text("Default")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                }

                // Skills badges
                HStack(spacing: 4) {
                    ForEach(Array(agent.skills).prefix(3), id: \.self) { skill in
                        SkillBadge(skill: skill)
                    }

                    if agent.skills.count > 3 {
                        Text("+\(agent.skills.count - 3)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Edit Agent")

                    Menu {
                        Button("Duplicate", action: onDuplicate)
                        if !agent.isDefault {
                            Divider()
                            Button("Delete", role: .destructive, action: onDelete)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                    .help("More Actions")
                }
            }

            // Active indicator
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.1) : (isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Skill Badge

struct SkillBadge: View {
    let skill: AgentSkill

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: skill.icon)
                .font(.system(size: 8))

            Text(skill.rawValue)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    AgentStudioView(
        manager: AgentStudioManager.shared,
        isSheetPresented: .constant(false)
    )
    .frame(width: 400, height: 300)
    .padding()
}
