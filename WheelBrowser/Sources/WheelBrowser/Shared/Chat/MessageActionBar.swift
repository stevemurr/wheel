import SwiftUI

/// Hover-reveal action toolbar for chat messages.
/// User messages: Edit, Copy.
/// Assistant messages: Copy, Regenerate, Branch navigator.
struct MessageActionBar: View {
    let message: ChatMessage
    let isHovered: Bool
    var onEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onSwitchBranch: ((Int) -> Void)?

    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 6) {
            if message.role == .user {
                // Edit button
                if let onEdit = onEdit {
                    actionButton(icon: "pencil", label: "Edit", action: onEdit)
                }

                // Copy button
                copyButton
            } else if message.role == .assistant {
                // Copy button
                copyButton

                // Regenerate button
                if let onRegenerate = onRegenerate, !message.isStreaming {
                    actionButton(icon: "arrow.clockwise", label: "Regenerate", action: onRegenerate)
                }

                // Branch navigator
                if message.totalBranches > 1 {
                    branchNavigator
                }
            }

            Spacer()
        }
        .opacity(isHovered || showCopied ? 1.0 : 0.0)
        .animation(AppAnimation.standardOut, value: isHovered)
    }

    // MARK: - Components

    private var copyButton: some View {
        actionButton(
            icon: showCopied ? "checkmark" : "doc.on.doc",
            label: showCopied ? "Copied" : "Copy",
            color: showCopied ? .green : .secondary,
            action: {
                PasteboardHelper.copy(message.content)
                showCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showCopied = false
                }
            }
        )
    }

    private var branchNavigator: some View {
        HStack(spacing: 2) {
            Button(action: {
                let prev = max(0, message.branchIndex - 1)
                onSwitchBranch?(prev)
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(message.branchIndex == 0)

            Text("\(message.branchIndex + 1)/\(message.totalBranches)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: {
                let next = min(message.totalBranches - 1, message.branchIndex + 1)
                onSwitchBranch?(next)
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(message.branchIndex >= message.totalBranches - 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }

    private func actionButton(
        icon: String,
        label: String,
        color: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }
}
