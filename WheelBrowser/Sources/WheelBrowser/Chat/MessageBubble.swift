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
                            .font(.system(size: 12))
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
                .text {
                    ForegroundColor(.white)
                    FontSize(13)
                }
                .paragraph { configuration in
                    configuration.label
                        .markdownMargin(top: 0, bottom: 4)
                }
                .code {
                    ForegroundColor(.white.opacity(0.95))
                    BackgroundColor(.white.opacity(0.2))
                    FontSize(12)
                }
                .link {
                    ForegroundColor(.white)
                    UnderlineStyle(.single)
                }
        default:
            return Theme()
                .text {
                    ForegroundColor(.primary)
                    FontSize(13)
                }
                .paragraph { configuration in
                    configuration.label
                        .markdownMargin(top: 0, bottom: 4)
                }
                .code {
                    FontFamilyVariant(.monospaced)
                    FontSize(12)
                    BackgroundColor(Color(nsColor: .controlBackgroundColor))
                }
                .codeBlock { configuration in
                    configuration.label
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .markdownMargin(top: 4, bottom: 4)
                }
                .link {
                    ForegroundColor(.accentColor)
                }
                .strong {
                    FontWeight(.semibold)
                }
                .heading1 { configuration in
                    configuration.label
                        .markdownTextStyle { FontSize(14); FontWeight(.bold) }
                        .markdownMargin(top: 8, bottom: 4)
                }
                .heading2 { configuration in
                    configuration.label
                        .markdownTextStyle { FontSize(13); FontWeight(.bold) }
                        .markdownMargin(top: 6, bottom: 4)
                }
                .heading3 { configuration in
                    configuration.label
                        .markdownTextStyle { FontSize(13); FontWeight(.semibold) }
                        .markdownMargin(top: 4, bottom: 2)
                }
                .listItem { configuration in
                    configuration.label
                        .markdownMargin(top: 2, bottom: 2)
                }
        }
    }
}
