import SwiftUI

// MARK: - Filter List Settings View

/// Settings view for managing external filter lists
struct FilterListSettingsView: View {
    @ObservedObject private var manager = FilterListManager.shared
    @State private var showingAddSheet = false
    @State private var newListURL = ""
    @State private var newListName = ""
    @State private var urlError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External Filter Lists")
                        .font(.headline)

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
                        Label("Update All", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(manager.isUpdating)
            }

            // Progress bar during update
            if manager.isUpdating {
                ProgressView(value: manager.updateProgress)
                    .progressViewStyle(.linear)
            }

            // Filter list rows
            ForEach(manager.filterLists) { filterList in
                FilterListRow(filterList: filterList)
            }

            // Add button
            Button(action: { showingAddSheet = true }) {
                Label("Add Filter List", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            // Info text
            Text("External filter lists like EasyList provide community-maintained blocking rules. Lists are automatically converted to WebKit format.")
                .font(.caption2)
                .foregroundColor(.secondary)

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

// MARK: - Filter List Row

struct FilterListRow: View {
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

// MARK: - Add Filter List Sheet

struct AddFilterListSheet: View {
    @Binding var url: String
    @Binding var name: String
    @Binding var error: String?
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Filter List")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filter List URL")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("https://example.com/filters.txt", text: $url)
                    .textFieldStyle(.roundedBorder)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("My Filter List", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Add", action: onAdd)
                    .keyboardShortcut(.return)
                    .disabled(url.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Preview

#Preview {
    Form {
        Section("Filter Lists") {
            FilterListSettingsView()
        }
    }
    .formStyle(.grouped)
    .frame(width: 500, height: 400)
}
