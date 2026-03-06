import SwiftUI

/// Small pill button in message bubbles showing language icon + truncated title.
/// Tap opens the artifact panel.
struct ArtifactChip: View {
    let artifact: ChatArtifact
    var onTap: () -> Void

    @State private var isHovered = false

    private var iconName: String {
        switch artifact.type {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "doc.richtext"
        case .html: return "globe"
        case .json: return "curlybraces"
        case .plainText: return "doc.text"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.85))

                Text(truncatedTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.84 : 0.68))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(artifact.title)
    }

    private var truncatedTitle: String {
        if artifact.title.count > 25 {
            return String(artifact.title.prefix(22)) + "..."
        }
        return artifact.title
    }
}
