import SwiftUI
import MarkdownUI
import AppKit

// MARK: - Typing Indicator (for ChatPanel)

struct ChatPanelTypingIndicator: View {
    @State private var animatingDots = [false, false, false]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animatingDots[index] ? 1.0 : 0.5)
                    .opacity(animatingDots[index] ? 1.0 : 0.4)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                animatingDots[i] = true
            }
        }
    }
}

// MARK: - Streaming Cursor Indicator

struct ChatPanelStreamingCursor: View {
    @State private var showCursor = true

    var body: some View {
        Text("|")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.purple.opacity(showCursor ? 0.8 : 0.0))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    showCursor.toggle()
                }
            }
    }
}

// MARK: - Pulsing Loading Dot

struct ChatPanelPulsingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.purple)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Suggested Prompt Chip

struct ChatPanelPromptChip: View {
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .opacity(isHovered ? 1.0 : 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.purple.opacity(isHovered ? 0.5 : 0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Panel that displays chat conversation above the OmniBar
struct ChatResponsePanel: View {
    @ObservedObject var agentManager: AgentManager
    @Binding var isVisible: Bool
    let onDismiss: () -> Void

    @State private var isHovering = false
    @State private var lastScrollTime: Date = .distantPast

    private let maxHeight: CGFloat = 500

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
                .stroke(Color.purple.opacity(0.5), lineWidth: 1.5)
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

            Text("Claude")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if agentManager.isLoading {
                ChatPanelPulsingDot()
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
                VStack(spacing: 8) {
                    if agentManager.messages.isEmpty {
                        emptyState
                            .padding(.top, 30)
                    } else {
                        ForEach(agentManager.messages) { message in
                            ChatPanelMessageBubble(message: message)
                                .id(message.id)
                        }

                        // Invisible anchor at the bottom for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: agentManager.messages.count) { _, _ in
                // Scroll to bottom on new message
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: agentManager.messages.last?.content) { _, _ in
                // Throttled scroll during streaming (max once per 100ms)
                let now = Date()
                if now.timeIntervalSince(lastScrollTime) > 0.1 {
                    lastScrollTime = now
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("Chat with Claude")
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

            // Accent bar for assistant messages
            if message.role == .assistant {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role indicator (simplified - removed for assistant to reduce clutter)
                if message.role == .user || message.role == .system || message.role == .thinking {
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
                }

                // Message content
                Group {
                    if message.content.isEmpty && message.isStreaming {
                        ChatPanelTypingIndicator()
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Markdown(message.content)
                                .markdownTheme(markdownTheme)
                                .textSelection(.enabled)

                            if message.isStreaming {
                                ChatPanelStreamingCursor()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 60, alignment: message.role == .user ? .trailing : .leading)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: message.role == .user ? 400 : .infinity, alignment: message.role == .user ? .trailing : .leading)

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
        case .assistant: return "Claude"
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

