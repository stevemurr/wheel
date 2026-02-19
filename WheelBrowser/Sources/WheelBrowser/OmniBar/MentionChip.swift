import SwiftUI

/// A chip displaying a mention with optional remove button
struct MentionChip: View {
    let mention: Mention
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mention.icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(iconColor)

            Text("@\(mention.displayTitle)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contentShape(Capsule())
    }

    private var iconColor: Color {
        switch mention {
        case .currentPage:
            return .purple
        case .tab:
            return .blue
        case .semanticResult:
            return .orange
        case .history:
            return .green
        }
    }

    private var backgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        iconColor.opacity(0.3)
    }
}

/// A row in the mention suggestions dropdown
struct MentionSuggestionRow: View {
    let suggestion: MentionSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    private var domain: String {
        guard let urlString = suggestion.mention.url,
              let url = URL(string: urlString),
              let host = url.host else {
            return ""
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            iconView
                .frame(width: 24, height: 24)

            // Title and URL
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.mention.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let url = suggestion.mention.url {
                    Text(formatURL(url))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Type badge
            Text(suggestion.mention.typeBadge)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(badgeColor.opacity(0.1))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.purple.opacity(0.2)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color.clear
    }

    private var badgeColor: Color {
        switch suggestion.mention {
        case .currentPage:
            return .purple
        case .tab:
            return .blue
        case .semanticResult:
            return .orange
        case .history:
            return .green
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch suggestion.mention {
        case .tab:
            // Favicon-like icon for tabs
            if !domain.isEmpty {
                let initial = String(domain.prefix(1)).uppercased()
                Text(initial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(colorForDomain(domain))
                    )
            } else {
                fallbackIcon
            }

        case .semanticResult:
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.orange.opacity(0.1))
                )

        case .currentPage:
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundColor(.purple)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.purple.opacity(0.1))
                )

        case .history:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundColor(.green)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.green.opacity(0.1))
                )
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "square.on.square")
            .font(.system(size: 12))
            .foregroundColor(.blue)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.blue.opacity(0.1))
            )
    }

    private func formatURL(_ urlString: String) -> String {
        var url = urlString
        url = url.replacingOccurrences(of: "https://", with: "")
        url = url.replacingOccurrences(of: "http://", with: "")
        url = url.replacingOccurrences(of: "www.", with: "")
        if url.count > 40 {
            url = String(url.prefix(37)) + "..."
        }
        return url
    }

    private func colorForDomain(_ domain: String) -> Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
        ]
        let hash = domain.utf8.reduce(0) { $0 &+ Int($1) }
        return colors[abs(hash) % colors.count]
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Chips
        HStack {
            MentionChip(mention: .currentPage, onRemove: {})
            MentionChip(
                mention: .tab(id: UUID(), title: "GitHub", url: "https://github.com"),
                onRemove: {}
            )
            MentionChip(
                mention: .semanticResult(id: UUID(), title: "Swift Documentation", url: "https://swift.org/docs"),
                onRemove: {}
            )
        }

        Divider()

        // Suggestion rows
        VStack(spacing: 4) {
            MentionSuggestionRow(
                suggestion: MentionSuggestion(
                    mention: .tab(id: UUID(), title: "GitHub - Your Repositories", url: "https://github.com/dashboard"),
                    score: 800
                ),
                isSelected: true,
                onSelect: {}
            )

            MentionSuggestionRow(
                suggestion: MentionSuggestion(
                    mention: .semanticResult(id: UUID(), title: "Swift Language Guide", url: "https://docs.swift.org/guide"),
                    score: 600
                ),
                isSelected: false,
                onSelect: {}
            )
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    .padding()
    .frame(width: 400)
}
