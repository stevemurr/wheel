import SwiftUI

struct ChatContextBadgeRow: View {
    let badges: [ChatContextBadge]
    var compact: Bool = false

    var body: some View {
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: compact ? 6 : 8) {
                    ForEach(badges) { badge in
                        ChatContextBadgeCapsule(badge: badge, compact: compact)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChatContextBadgeCapsule: View {
    let badge: ChatContextBadge
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            Image(systemName: badgeSystemImage)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundColor(badgeTintColor)

            Text(badgeDisplayName)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundColor(.primary)

            if let title = badge.title {
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let detail = badge.detail {
                Text(detail)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(compact ? 0.82 : 0.72))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(badgeTintColor.opacity(0.18), lineWidth: 1)
        )
        .help(helpText)
    }

    private var helpText: String {
        var parts = [badgeDisplayName]
        if let title = badge.title, !title.isEmpty {
            parts.append(title)
        }
        if let detail = badge.detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let resourceURI = badge.resourceURI?.rawValue, !resourceURI.isEmpty {
            parts.append(resourceURI)
        }
        if let url = badge.url, !url.isEmpty {
            parts.append(url)
        }
        return parts.joined(separator: " • ")
    }

    private var badgeDisplayName: String {
        switch badge.kind {
        case .website:
            return "Website"
        case .history:
            return "History"
        case .webSearch:
            return "Web Search"
        case .readingList:
            return "Reading List"
        case .domain:
            return "Domain"
        case .miniWindow:
            return "Mini Window"
        case .note:
            return "Note"
        case .fabricResource:
            return badge.presentation?.categoryLabel ?? "Resource"
        case .tool:
            return "Tool"
        case .toolResult:
            return "Tool Result"
        }
    }

    private var badgeSystemImage: String {
        switch badge.kind {
        case .website:
            return "globe"
        case .history:
            return "clock.arrow.circlepath"
        case .webSearch:
            return "sparkle.magnifyingglass"
        case .readingList:
            return "bookmark"
        case .domain:
            return "link"
        case .miniWindow:
            return "pip"
        case .note:
            return "note.text"
        case .fabricResource:
            return badge.presentation?.systemImage ?? "doc.text"
        case .tool:
            return "hammer"
        case .toolResult:
            return "checkmark.seal"
        }
    }

    private var badgeTintColor: Color {
        switch badge.kind {
        case .website:
            return .blue
        case .history:
            return .green
        case .webSearch:
            return .teal
        case .readingList:
            return .indigo
        case .domain:
            return .cyan
        case .miniWindow:
            return .mint
        case .note:
            return .accentColor
        case .fabricResource:
            return .chatBadgeTint(badge.presentation?.tint ?? "secondary")
        case .tool:
            return .orange
        case .toolResult:
            return .purple
        }
    }
}

private extension Color {
    static func chatBadgeTint(_ token: String) -> Color {
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
