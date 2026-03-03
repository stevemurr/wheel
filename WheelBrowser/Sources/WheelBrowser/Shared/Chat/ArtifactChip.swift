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
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.purple.opacity(0.7))

                Text(truncatedTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.purple.opacity(isHovered ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
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
