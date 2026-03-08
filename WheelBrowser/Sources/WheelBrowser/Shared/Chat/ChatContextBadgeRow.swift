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
            Image(systemName: badge.kind.systemImage)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundColor(badge.kind.tintColor)

            Text(badge.kind.displayName)
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
                .stroke(badge.kind.tintColor.opacity(0.18), lineWidth: 1)
        )
        .help(helpText)
    }

    private var helpText: String {
        var parts = [badge.kind.displayName]
        if let title = badge.title, !title.isEmpty {
            parts.append(title)
        }
        if let detail = badge.detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let url = badge.url, !url.isEmpty {
            parts.append(url)
        }
        return parts.joined(separator: " • ")
    }
}

private extension ChatContextBadge.Kind {
    var displayName: String {
        switch self {
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
        case .tool:
            return "Tool"
        case .toolResult:
            return "Tool Result"
        }
    }

    var systemImage: String {
        switch self {
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
        case .tool:
            return "hammer"
        case .toolResult:
            return "checkmark.seal"
        }
    }

    var tintColor: Color {
        switch self {
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
        case .tool:
            return .orange
        case .toolResult:
            return .purple
        }
    }
}
