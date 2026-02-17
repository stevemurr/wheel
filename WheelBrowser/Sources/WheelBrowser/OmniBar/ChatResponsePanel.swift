import SwiftUI
import MarkdownUI

/// Panel that displays chat conversation above the OmniBar
struct ChatResponsePanel: View {
    @ObservedObject var agentManager: AgentManager
    @Binding var isVisible: Bool
    let onDismiss: () -> Void

    @State private var isHovering = false

    private let maxHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            // Header with dismiss button
            header

            Divider()
                .opacity(0.5)

            // Messages area
            messagesArea
        }
        .frame(maxWidth: 700)
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: -8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.purple)

            Text("AI Assistant")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if agentManager.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            Menu {
                Button("Clear Chat") {
                    agentManager.clearMessages()
                }
                Divider()
                Button("Reset Agent", role: .destructive) {
                    Task { await agentManager.resetAgent() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .separatorColor).opacity(0.05))
    }

    // MARK: - Messages Area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    if agentManager.messages.isEmpty {
                        emptyState
                            .padding(.top, 30)
                    } else {
                        ForEach(agentManager.messages) { message in
                            ChatPanelMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: agentManager.messages.count) { _, _ in
                if let lastMessage = agentManager.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("Start a conversation")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text("Ask questions about the current page")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let error = agentManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task { await agentManager.initialize() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

/// Compact message bubble for the chat panel
struct ChatPanelMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role indicator
                HStack(spacing: 4) {
                    if message.role != .user {
                        Image(systemName: roleIcon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(roleColor)
                    }

                    Text(roleLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    if message.role == .user {
                        Image(systemName: roleIcon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(roleColor)
                    }
                }

                // Message content
                Group {
                    if message.content.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 3, height: 3)
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        Markdown(message.content)
                            .markdownTheme(markdownTheme)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if message.role != .user {
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 1)
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .purple
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
