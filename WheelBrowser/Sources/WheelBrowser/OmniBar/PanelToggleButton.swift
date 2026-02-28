import SwiftUI

/// Reusable chevron toggle button for expanding/collapsing OmniBar panels.
/// Used by chat, semantic, agent, and reading list panel toggles.
struct PanelToggleButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale))
    }
}
