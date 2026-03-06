import SwiftUI

/// Modal sheet for creating a new module via natural language prompt.
struct ModulePromptSheet: View {
    let store: ModuleStore
    let onDismiss: () -> Void

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var generatedManifest: ModuleManifest?
    @State private var error: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Create Module")
                .font(.headline)

            Spacer()

            Button("Cancel") {
                dismiss()
                onDismiss()
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let manifest = generatedManifest {
            previewView(manifest: manifest)
        } else {
            promptInput
        }
    }

    // MARK: - Prompt Input

    private var promptInput: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Describe what you want:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g., Build me an ad blocker, Make all sites dark mode, Show crypto prices",
                    text: $prompt
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { generateModule() }
            }

            // Quick suggestions
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick ideas:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
                    SuggestionChip("Ad blocker") { prompt = "Build me an ad blocker" }
                    SuggestionChip("Dark mode") { prompt = "Make all websites dark mode" }
                    SuggestionChip("Bitcoin price") { prompt = "Show me a bitcoin price widget" }
                    SuggestionChip("Page summarizer") { prompt = "Create a page summarizer tool" }
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            HStack {
                Spacer()

                Button(action: generateModule) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Generate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
            }
        }
        .padding()
    }

    // MARK: - Preview

    private func previewView(manifest: ModuleManifest) -> some View {
        VStack(spacing: 16) {
            // Module info
            HStack(spacing: 12) {
                Image(systemName: moduleTypeIcon(manifest.moduleType))
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manifest.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(manifest.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(manifest.moduleType.rawValue.replacingOccurrences(of: "_", with: "").capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            // Permissions
            if !manifest.permissions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This module requires:")
                        .font(.system(size: 13, weight: .medium))

                    ForEach(manifest.permissions, id: \.self) { permission in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                            Text(permission.displayName)
                                .font(.system(size: 12))
                        }
                    }
                }
            }

            // Summary
            VStack(alignment: .leading, spacing: 4) {
                if manifest.contentRules != nil {
                    summaryRow(icon: "shield", text: "\(manifest.contentRules!.count) blocking rules")
                }
                if manifest.styles != nil {
                    summaryRow(icon: "paintbrush", text: "CSS styles will be injected")
                }
                if manifest.contentScript != nil {
                    summaryRow(icon: "doc.text", text: "Content script will run on pages")
                }
                if manifest.backgroundScript != nil {
                    summaryRow(icon: "gear", text: "Background script will run in sandbox")
                }
            }

            Spacer()

            HStack {
                Button("Back") {
                    generatedManifest = nil
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Install Module") {
                    store.install(manifest)
                    dismiss()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func summaryRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func moduleTypeIcon(_ type: ModuleType) -> String {
        switch type {
        case .widget: return "square.grid.2x2"
        case .extension_: return "puzzlepiece.extension"
        case .skill: return "wrench"
        case .blocker: return "shield"
        }
    }

    // MARK: - Generation

    private func generateModule() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isGenerating = true
        error = nil

        Task {
            do {
                let generator = ModuleGenerator()
                let manifest = try await generator.generate(prompt: prompt)

                await MainActor.run {
                    generatedManifest = manifest
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Suggestion Chip

private struct SuggestionChip: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
