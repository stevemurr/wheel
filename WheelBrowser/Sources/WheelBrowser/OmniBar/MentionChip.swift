import Fabric
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
            withAnimation(AppAnimation.standard) {
                isHovering = hovering
            }
        }
        .contentShape(Capsule())
    }

    private var iconColor: Color {
        .fabricTint(mention.tintToken)
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
        suggestion.mention.url?.urlCleanDomain ?? ""
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

                if let subtitle = suggestion.mention.subtitleText ?? suggestion.mention.url.map(formatURL) {
                    Text(subtitle)
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
            withAnimation(AppAnimation.quick) {
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
        .fabricTint(suggestion.mention.tintToken)
    }

    @ViewBuilder
    private var iconView: some View {
        switch suggestion.mention {
        case .pageSnapshot:
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.orange.opacity(0.1))
                )

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

        case .overlay:
            Image(systemName: "pip")
                .font(.system(size: 12))
                .foregroundColor(.mint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.mint.opacity(0.1))
                )

        case .note:
            Image(systemName: "note.text")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.12))
                )

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

        case .web:
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundColor(.teal)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.teal.opacity(0.1))
                )

        case .readingList:
            Image(systemName: "bookmark")
                .font(.system(size: 12))
                .foregroundColor(.indigo)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.indigo.opacity(0.1))
                )

        case .domain:
            Image(systemName: "link")
                .font(.system(size: 12))
                .foregroundColor(.cyan)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.cyan.opacity(0.1))
                )

        case .fabricResource:
            genericIcon(
                systemName: suggestion.mention.icon,
                tintColor: badgeColor
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

    private func genericIcon(systemName: String, tintColor: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12))
            .foregroundColor(tintColor)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(tintColor.opacity(0.1))
            )
    }

    private func formatURL(_ urlString: String) -> String {
        URLFormatter.shared.displayURL(urlString, maxLength: 40)
    }

    private func colorForDomain(_ domain: String) -> Color {
        DomainColor.color(for: domain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Chips
        HStack {
            MentionChip(mention: .currentPage, onRemove: {})
            MentionChip(
                mention: .pageSnapshot(
                    id: UUID(),
                    title: "Checkout flow",
                    url: "https://example.com/checkout"
                ),
                onRemove: {}
            )
            MentionChip(
                mention: .tab(id: UUID(), title: "GitHub", url: "https://github.com"),
                onRemove: {}
            )
            MentionChip(
                mention: .semanticResult(id: UUID(), title: "Swift Documentation", url: "https://swift.org/docs"),
                onRemove: {}
            )
            MentionChip(
                mention: .note(id: UUID(), title: "Planning note", excerpt: "Ship note mentions next."),
                onRemove: {}
            )
            MentionChip(
                mention: .fabricResource(
                    FabricMentionReference(
                        uri: FabricURI(appID: "external.docs", kind: "document", id: "roadmap"),
                        kind: "document",
                        title: "Platform Roadmap",
                        summary: "Q3 planning document",
                        url: nil,
                        presentation: .init(
                            systemImage: "doc.richtext",
                            tint: "gray",
                            subtitle: "Q3 planning document",
                            categoryLabel: "Document"
                        )
                    )
                ),
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
                    mention: .pageSnapshot(
                        id: UUID(),
                        title: "Checkout flow",
                        url: "https://example.com/checkout"
                    ),
                    score: 780
                ),
                isSelected: false,
                onSelect: {}
            )

            MentionSuggestionRow(
                suggestion: MentionSuggestion(
                    mention: .note(id: UUID(), title: "Release plan", excerpt: "Tighten chat mentions and note actions."),
                    score: 700
                ),
                isSelected: false,
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

            MentionSuggestionRow(
                suggestion: MentionSuggestion(
                    mention: .fabricResource(
                        FabricMentionReference(
                            uri: FabricURI(appID: "external.docs", kind: "document", id: "roadmap"),
                            kind: "document",
                            title: "Platform Roadmap",
                            summary: "Q3 planning document",
                            url: nil,
                            presentation: .init(
                                systemImage: "doc.richtext",
                                tint: "gray",
                                subtitle: "Q3 planning document",
                                categoryLabel: "Document"
                            )
                        )
                    ),
                    score: 550
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

private extension Color {
    static func fabricTint(_ token: String) -> Color {
        switch token.lowercased() {
        case "accent":
            return .accentColor
        case "blue":
            return .blue
        case "purple":
            return .purple
        case "orange":
            return .orange
        case "mint":
            return .mint
        case "green":
            return .green
        case "teal":
            return .teal
        case "indigo":
            return .indigo
        case "cyan":
            return .cyan
        case "red":
            return .red
        case "pink":
            return .pink
        case "yellow":
            return .yellow
        case "gray", "grey", "secondary":
            return .secondary
        default:
            return .secondary
        }
    }
}
