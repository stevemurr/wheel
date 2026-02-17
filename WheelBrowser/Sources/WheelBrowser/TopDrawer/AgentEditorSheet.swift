import SwiftUI

/// Modal sheet for creating or editing an agent
struct AgentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: AgentStudioManager

    // Editing state
    let existingAgent: AgentConfig?

    @State private var name: String = ""
    @State private var selectedIcon: String = "sparkles"
    @State private var soul: String = ""
    @State private var selectedSkills: Set<AgentSkill> = []
    @State private var selectedModel: String = "llama3.2:latest"
    @State private var isDefault: Bool = false

    private var isEditing: Bool {
        existingAgent != nil
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name section
                    nameSection

                    Divider()

                    // Icon picker
                    iconSection

                    Divider()

                    // Soul / System prompt
                    soulSection

                    Divider()

                    // Skills
                    skillsSection

                    Divider()

                    // Model picker
                    modelSection

                    // Default toggle
                    defaultSection
                }
                .padding(20)
            }

            Divider()

            // Footer with action buttons
            footer
        }
        .frame(width: 500, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadExistingAgent()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Agent" : "Create Agent")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            TextField("Enter agent name", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 10), spacing: 8) {
                ForEach(AgentConfig.availableIcons, id: \.self) { icon in
                    IconButton(
                        icon: icon,
                        isSelected: selectedIcon == icon,
                        action: { selectedIcon = icon }
                    )
                }
            }
        }
    }

    // MARK: - Soul Section

    private var soulSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Soul")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("System prompt / personality")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            TextEditor(text: $soul)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 120)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Skills Section

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Skills")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button(selectedSkills.count == AgentSkill.allCases.count ? "Deselect All" : "Select All") {
                    if selectedSkills.count == AgentSkill.allCases.count {
                        selectedSkills.removeAll()
                    } else {
                        selectedSkills = Set(AgentSkill.allCases)
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }

            VStack(spacing: 6) {
                ForEach(AgentSkill.allCases, id: \.self) { skill in
                    SkillToggleRow(
                        skill: skill,
                        isEnabled: selectedSkills.contains(skill),
                        onToggle: {
                            if selectedSkills.contains(skill) {
                                selectedSkills.remove(skill)
                            } else {
                                selectedSkills.insert(skill)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("", selection: $selectedModel) {
                ForEach(AgentConfig.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    // MARK: - Default Section

    private var defaultSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default Agent")
                    .font(.system(size: 13, weight: .medium))

                Text("Use this agent for new workspaces")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isDefault)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isEditing && existingAgent?.isDefault != true {
                Button("Delete", role: .destructive) {
                    if let agent = existingAgent {
                        manager.deleteAgent(id: agent.id)
                        dismiss()
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(isEditing ? "Save" : "Create") {
                saveAgent()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func loadExistingAgent() {
        guard let agent = existingAgent else { return }
        name = agent.name
        selectedIcon = agent.icon
        soul = agent.soul
        selectedSkills = agent.skills
        selectedModel = agent.model
        isDefault = agent.isDefault
    }

    private func saveAgent() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = existingAgent {
            var updated = existing
            updated.name = trimmedName
            updated.icon = selectedIcon
            updated.soul = soul
            updated.skills = selectedSkills
            updated.model = selectedModel
            updated.isDefault = isDefault
            manager.updateAgent(updated)
        } else {
            manager.createAgent(
                name: trimmedName,
                icon: selectedIcon,
                soul: soul,
                skills: selectedSkills,
                model: selectedModel
            )
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skill Toggle Row

struct SkillToggleRow: View {
    let skill: AgentSkill
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: skill.icon)
                .frame(width: 20)
                .foregroundColor(isEnabled ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.rawValue)
                    .font(.system(size: 12, weight: .medium))

                Text(skill.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isEnabled ? 0.5 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Preview

#Preview {
    AgentEditorSheet(manager: AgentStudioManager.shared, existingAgent: nil)
}
