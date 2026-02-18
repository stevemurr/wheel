import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Role indicator
                HStack(spacing: 5) {
                    if message.role != .user {
                        Image(systemName: roleIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(roleColor)
                    }

                    Text(roleLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    if message.role == .user {
                        Image(systemName: roleIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(roleColor)
                    }
                }

                // Message content
                Group {
                    if message.content.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .padding(.vertical, 8)
                    } else if message.isStreaming {
                        // Fast plain text rendering during streaming
                        Text(message.content)
                            .font(.system(size: 13))
                            .foregroundColor(message.role == .user ? .white : .primary)
                    } else {
                        // Full markdown rendering when complete
                        Markdown(message.content)
                            .markdownTheme(markdownTheme)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if message.role != .user {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .accentColor
        case .system: return .orange
        case .thinking: return .purple
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .thinking: return "Thinking"
        }
    }

    private var roleIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "info.circle.fill"
        case .thinking: return "brain"
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.accentColor
        case .assistant:
            Color(nsColor: .controlBackgroundColor)
        case .system:
            Color.orange.opacity(0.15)
        case .thinking:
            Color.purple.opacity(0.15)
        }
    }

    private var markdownTheme: Theme {
        switch message.role {
        case .user:
            return Theme()
                .text { ForegroundColor(.white) }
                .code { ForegroundColor(.white.opacity(0.95)); BackgroundColor(.white.opacity(0.2)) }
                .link { ForegroundColor(.white); UnderlineStyle(.single) }
        default:
            return Theme.gitHub
        }
    }
}
