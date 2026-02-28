import SwiftUI

struct ContentBlockingSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var contentBlocker = ContentBlockerManager.shared
    @ObservedObject private var filterListManager = FilterListManager.shared

    var body: some View {
        Section("Content Blocking") {
            // Master toggle
            Toggle("Enable Content Blocking", isOn: $settings.adBlockingEnabled)

            // Status indicator
            if contentBlocker.isCompiling {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Compiling blocking rules...")
                        .foregroundColor(.secondary)
                }
            } else if let error = contentBlocker.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } else if contentBlocker.contentRuleList != nil {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text(contentBlocker.statusDescription)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } else if contentBlocker.enabledCategories.isEmpty {
                HStack {
                    Image(systemName: "shield.slash")
                        .foregroundColor(.secondary)
                    Text("No blocking categories enabled")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            // All blocking options in one flat list
            if settings.adBlockingEnabled {
                // Built-in blocking categories
                ForEach(BlockingCategory.allCases, id: \.self) { category in
                    CategoryToggleRow(
                        category: category,
                        isEnabled: contentBlocker.isEnabled(category),
                        ruleCount: ContentBlockerManager.approximateRuleCounts[category] ?? 0
                    ) {
                        contentBlocker.toggle(category)
                    }
                }

                // Built-in filter lists (EasyList, EasyPrivacy)
                ForEach(filterListManager.filterLists.filter { $0.isBuiltIn }) { filterList in
                    FilterListToggleRow(filterList: filterList)
                }
            }

            Button("Refresh Blocking Rules") {
                Task {
                    await contentBlocker.refreshRules()
                }
            }
            .disabled(contentBlocker.isCompiling)
        }
    }
}

// MARK: - Supporting Views

/// Row for displaying a blocking category with toggle
struct CategoryToggleRow: View {
    let category: BlockingCategory
    let isEnabled: Bool
    let ruleCount: Int
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .frame(width: 20)
                .foregroundColor(isEnabled ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                Text("\(ruleCount) rules - \(category.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

/// Row for displaying a filter list with toggle (matching CategoryToggleRow style)
struct FilterListToggleRow: View {
    let filterList: FilterList
    @ObservedObject private var manager = FilterListManager.shared

    var body: some View {
        HStack {
            Image(systemName: "list.bullet.rectangle")
                .frame(width: 20)
                .foregroundColor(filterList.isEnabled ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(filterList.name)
                if filterList.ruleCount > 0 {
                    Text("\(formatRuleCount(filterList.ruleCount)) rules - Community filter list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Community filter list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { filterList.isEnabled },
                set: { newValue in
                    manager.setEnabled(newValue, for: filterList)
                }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.toggleFilterList(filterList)
        }
    }

    private func formatRuleCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - External Filter Lists View (Inline)

/// Inline view for external filter lists within the Content Blocking section
struct ExternalFilterListsView: View {
    @ObservedObject private var manager = FilterListManager.shared
    @State private var showingAddSheet = false
    @State private var newListURL = ""
    @State private var newListName = ""
    @State private var urlError: String?

    var body: some View {
        DisclosureGroup {
            // Progress bar during update
            if manager.isUpdating {
                ProgressView(value: manager.updateProgress)
                    .progressViewStyle(.linear)
            }

            // Filter list rows
            ForEach(manager.filterLists) { filterList in
                ExternalFilterListRow(filterList: filterList)
            }

            // Add button
            Button(action: { showingAddSheet = true }) {
                Label("Add Filter List", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            // WebKit limit warning
            if manager.totalEnabledRuleCount > 45_000 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Approaching WebKit's 50,000 rule limit. Some rules may be truncated.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .frame(width: 20)
                    .foregroundColor(manager.enabledCount > 0 ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("External Filter Lists")
                    Text("\(manager.enabledCount) enabled, \(formatRuleCount(manager.totalEnabledRuleCount)) rules")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Update all button
                Button(action: {
                    Task {
                        await manager.updateAll(forceUpdate: true)
                    }
                }) {
                    if manager.isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(manager.isUpdating)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddFilterListSheet(
                url: $newListURL,
                name: $newListName,
                error: $urlError,
                onAdd: addFilterList,
                onCancel: { showingAddSheet = false }
            )
        }
    }

    private func formatRuleCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func addFilterList() {
        guard let url = URL(string: newListURL),
              url.scheme == "http" || url.scheme == "https" else {
            urlError = "Please enter a valid HTTP(S) URL"
            return
        }

        let name = newListName.isEmpty ? url.lastPathComponent : newListName

        manager.addFilterList(name: name, url: url)

        // Fetch the new list
        Task {
            if let addedList = manager.filterLists.last {
                _ = try? await manager.updateFilterList(addedList, forceUpdate: true)
            }
        }

        // Reset and close
        newListURL = ""
        newListName = ""
        urlError = nil
        showingAddSheet = false
    }
}

// MARK: - External Filter List Row

struct ExternalFilterListRow: View {
    let filterList: FilterList
    @ObservedObject private var manager = FilterListManager.shared
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { filterList.isEnabled },
                set: { _ in manager.toggleFilterList(filterList) }
            ))
            .labelsHidden()

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(filterList.name)
                        .fontWeight(.medium)

                    if filterList.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }

                    if filterList.lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                HStack(spacing: 8) {
                    if filterList.ruleCount > 0 {
                        Text("\(formatRuleCount(filterList.ruleCount)) rules")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let lastUpdated = filterList.lastUpdated {
                        Text("Updated \(formatRelativeDate(lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if filterList.isEnabled {
                        Text("Not downloaded")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if let error = filterList.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Delete button (for non-built-in lists)
            if !filterList.isBuiltIn {
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .alert("Remove Filter List?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                manager.removeFilterList(filterList)
            }
        } message: {
            Text("This will remove \"\(filterList.name)\" and its rules.")
        }
    }

    private func formatRuleCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
