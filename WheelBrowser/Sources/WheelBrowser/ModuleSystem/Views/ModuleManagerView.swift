import SwiftUI

/// UI for managing installed modules — view, enable/disable, and remove.
struct ModuleManagerView: View {
    let store: ModuleStore

    @State private var selectedModule: ModuleInstance?
    @State private var showingDeleteConfirmation = false
    @State private var moduleToDelete: ModuleInstance?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.modules.isEmpty {
                emptyState
            } else {
                moduleList
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Remove Module?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let module = moduleToDelete {
                    store.remove(id: module.id)
                    if selectedModule?.id == module.id {
                        selectedModule = nil
                    }
                }
            }
        } message: {
            if let module = moduleToDelete {
                Text("'\(module.manifest.name)' will be permanently removed.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Installed Modules")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Text("\(store.modules.count) module\(store.modules.count == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No Modules Installed")
                .font(.headline)

            Text("Ask the AI to create modules like ad blockers, dark mode, or custom widgets.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Module List

    private var moduleList: some View {
        HSplitView {
            // Module list (left)
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.modules) { module in
                        ModuleListRow(
                            module: module,
                            isSelected: selectedModule?.id == module.id,
                            onToggle: { store.toggleEnabled(id: module.id) },
                            onSelect: { selectedModule = module },
                            onDelete: {
                                moduleToDelete = module
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minWidth: 220, idealWidth: 260)

            // Detail panel (right)
            if let module = selectedModule {
                ModuleDetailView(module: module, store: store)
            } else {
                Text("Select a module to view details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Module List Row

struct ModuleListRow: View {
    let module: ModuleInstance
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Module type icon
            Image(systemName: moduleTypeIcon)
                .font(.system(size: 14))
                .foregroundStyle(module.manifest.isEnabled ? .primary : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.manifest.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(module.manifest.isEnabled ? .primary : .secondary)
                    .lineLimit(1)

                Text(module.manifest.moduleType.rawValue.replacingOccurrences(of: "_", with: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }

            Spacer()

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Toggle("", isOn: Binding(
                get: { module.manifest.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }

    private var moduleTypeIcon: String {
        switch module.manifest.moduleType {
        case .widget: return "square.grid.2x2"
        case .extension_: return "puzzlepiece.extension"
        case .skill: return "wrench"
        case .blocker: return "shield"
        }
    }
}

// MARK: - Module Detail View

struct ModuleDetailView: View {
    let module: ModuleInstance
    let store: ModuleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(module.manifest.name)
                        .font(.system(size: 18, weight: .bold))

                    Text(module.manifest.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Metadata
                metadataSection

                Divider()

                // Permissions
                permissionsSection

                // Triggers
                triggersSection

                // Code sections
                if module.manifest.contentScript != nil {
                    codeSection(title: "Content Script", code: module.manifest.contentScript!)
                }
                if module.manifest.backgroundScript != nil {
                    codeSection(title: "Background Script", code: module.manifest.backgroundScript!)
                }
                if let styles = module.manifest.styles, !styles.isEmpty {
                    codeSection(title: "CSS Styles", code: styles.joined(separator: "\n"))
                }
                if module.manifest.contentRules != nil {
                    Text("Content Rules")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(module.manifest.contentRules!.count) blocking rules active")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow("Type", value: module.manifest.moduleType.rawValue.replacingOccurrences(of: "_", with: "").capitalized)
            metadataRow("Version", value: "\(module.manifest.version)")
            metadataRow("Created", value: module.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
            metadataRow("Updated", value: module.manifest.updatedAt.formatted(date: .abbreviated, time: .shortened))
            metadataRow("Status", value: module.manifest.isEnabled ? "Enabled" : "Disabled")
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(size: 12))
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions")
                .font(.system(size: 13, weight: .semibold))

            if module.manifest.permissions.isEmpty {
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(module.manifest.permissions, id: \.self) { permission in
                        Text(permission.displayName)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    // MARK: - Triggers

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Triggers")
                .font(.system(size: 13, weight: .semibold))

            ForEach(Array(module.manifest.triggers.enumerated()), id: \.offset) { _, trigger in
                HStack(spacing: 6) {
                    Image(systemName: triggerIcon(trigger.type))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(triggerDescription(trigger))
                        .font(.system(size: 12))
                }
            }
        }
    }

    private func triggerIcon(_ type: ModuleTrigger.TriggerType) -> String {
        switch type {
        case .pageLoad: return "globe"
        case .manual: return "hand.tap"
        case .schedule: return "clock"
        case .always: return "infinity"
        }
    }

    private func triggerDescription(_ trigger: ModuleTrigger) -> String {
        switch trigger.type {
        case .pageLoad:
            return "Page load: \(trigger.urlPattern ?? "*")"
        case .manual:
            return "Manual invocation"
        case .schedule:
            let minutes = (trigger.intervalSeconds ?? 300) / 60
            return "Every \(minutes) minutes"
        case .always:
            return "Always active"
        }
    }

    // MARK: - Code Section

    private func codeSection(title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private struct ArrangementResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = currentY + rowHeight
        }

        return ArrangementResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions
        )
    }
}
