import SwiftUI

/// Compact badge showing current model short name with dropdown for selection.
/// Isolated sub-view per Rule 13 to prevent OmniBar body re-evaluation.
struct ModelSelectorBadge: View {
    @ObservedObject private var settings = AppSettings.shared

    /// Short display name for the current model
    private var shortName: String {
        let model = settings.selectedModel
        // Extract just the model name (before any colon or slash)
        let base = model
            .components(separatedBy: "/").last ?? model
        // Truncate long names
        let name = base.components(separatedBy: ":").first ?? base
        if name.count > 12 {
            return String(name.prefix(10)) + "..."
        }
        return name
    }

    var body: some View {
        Menu {
            // Show current model with checkmark
            Button(action: {}) {
                Label(settings.selectedModel, systemImage: "checkmark")
            }
            .disabled(true)

            Divider()

            // Link to settings
            Button("Model Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } label: {
            Text(shortName)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
