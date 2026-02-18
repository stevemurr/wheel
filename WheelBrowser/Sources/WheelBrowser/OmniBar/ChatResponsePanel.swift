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

// MARK: - Streaming Markdown Content (Block-based rendering)

/// Splits markdown into completed blocks (cached) + streaming tail (re-renders)
/// This prevents O(n²) re-parsing by only re-rendering the active block
struct StreamingMarkdownContent: View {
    let content: String
    let theme: Theme

    // Split content into completed blocks and streaming tail
    private var blocks: (completed: [String], streaming: String) {
        splitIntoBlocks(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Completed blocks - each rendered once and cached by SwiftUI
            ForEach(Array(blocks.completed.enumerated()), id: \.offset) { index, block in
                Markdown(block)
                    .markdownTheme(theme)
                    .textSelection(.enabled)
                    .id("block-\(index)-\(block.hashValue)") // Stable ID prevents re-render
            }

            // Streaming tail - only this re-renders on updates
            if !blocks.streaming.isEmpty {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(blocks.streaming)
                        .font(.system(size: 13.5))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                    ChatPanelStreamingCursor()
                }
            } else {
                ChatPanelStreamingCursor()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Splits content into completed markdown blocks and the streaming tail
    private func splitIntoBlocks(_ text: String) -> (completed: [String], streaming: String) {
        guard !text.isEmpty else { return ([], "") }

        var completed: [String] = []
        var currentBlock = ""
        var inCodeBlock = false
        var inLatexBlock = false

        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track code block state
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
            }

            // Track LaTeX block state
            if trimmed.hasPrefix("$$") {
                inLatexBlock.toggle()
            }

            currentBlock += line
            if index < lines.count - 1 {
                currentBlock += "\n"
            }

            // Check if this completes a block (only if not in code/latex block)
            let isLastLine = index == lines.count - 1
            let nextLineEmpty = index + 1 < lines.count && lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty

            if !isLastLine && !inCodeBlock && !inLatexBlock {
                // Block boundaries: empty line, or end of code/latex block
                if trimmed.isEmpty && !currentBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Empty line = paragraph break
                    completed.append(currentBlock)
                    currentBlock = ""
                } else if trimmed.hasPrefix("```") && !inCodeBlock {
                    // Just closed a code block
                    completed.append(currentBlock)
                    currentBlock = ""
                } else if trimmed.hasPrefix("$$") && !inLatexBlock {
                    // Just closed a latex block
                    completed.append(currentBlock)
                    currentBlock = ""
                } else if trimmed.hasPrefix("#") && nextLineEmpty {
                    // Heading followed by empty line
                    completed.append(currentBlock)
                    currentBlock = ""
                }
            }
        }

        // Whatever remains is the streaming tail
        return (completed, currentBlock)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: -10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))

            Text("Chat")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            if agentManager.isLoading {
                ChatPanelPulsingDot()
                    .padding(.trailing, 4)
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
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Messages Area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(spacing: 14) {
                    if agentManager.messages.isEmpty {
                        emptyState
                            .padding(.top, 24)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
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
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text("Start a conversation")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Text("Ask questions about the current page")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if let error = agentManager.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.9))
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
        .padding(.vertical, 20)
    }
}

/// Compact message bubble for the chat panel
struct ChatPanelMessageBubble: View {
    let message: ChatMessage
    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Role indicator for user messages only
                if message.role == .user {
                    HStack(spacing: 4) {
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }

                // Message content
                Group {
                    if message.content.isEmpty && message.isStreaming {
                        ChatPanelTypingIndicator()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    } else if message.isStreaming {
                        // Streaming: render completed blocks + streaming tail
                        StreamingMarkdownContent(
                            content: message.content,
                            theme: markdownTheme
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else {
                        // Streaming complete: render full markdown
                        Markdown(message.content)
                            .markdownTheme(markdownTheme)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .frame(minWidth: 60, alignment: message.role == .user ? .trailing : .leading)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(bubbleBorder, lineWidth: 0.5)
                )

                // Action toolbar for assistant messages (copy button)
                if message.role == .assistant && !message.content.isEmpty && !message.isStreaming {
                    HStack(spacing: 8) {
                        Button(action: copyMessage) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .medium))
                                Text(showCopied ? "Copied" : "Copy")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(showCopied ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 1.0 : 0.6))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .opacity(isHovered || showCopied ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
                }
            }
            .frame(maxWidth: message.role == .user ? 400 : .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user {
                Spacer(minLength: 50)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showCopied = false
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .assistant:
            Color(nsColor: .textBackgroundColor).opacity(0.5)
        case .system:
            Color.orange.opacity(0.1)
        case .thinking:
            Color.purple.opacity(0.08)
        }
    }

    private var bubbleBorder: Color {
        switch message.role {
        case .user:
            return .clear
        case .assistant:
            return Color(nsColor: .separatorColor).opacity(0.3)
        case .system:
            return Color.orange.opacity(0.2)
        case .thinking:
            return Color.purple.opacity(0.15)
        }
    }

    private var markdownTheme: Theme {
        switch message.role {
        case .user:
            return Theme()
                .text {
                    ForegroundColor(.white)
                    FontSize(13.5)
                }
                .paragraph { configuration in
                    configuration.label
                        .markdownMargin(top: 0, bottom: 6)
                }
                .code {
                    ForegroundColor(.white.opacity(0.95))
                    BackgroundColor(.white.opacity(0.15))
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
                    FontSize(13.5)
                }
                .paragraph { configuration in
                    configuration.label
                        .markdownMargin(top: 0, bottom: 8)
                }
                .code {
                    FontFamilyVariant(.monospaced)
                    FontSize(12)
                    BackgroundColor(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
                }
                .codeBlock { configuration in
                    ScrollView(.horizontal, showsIndicators: false) {
                        configuration.label
                            .padding(10)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
                    )
                    .markdownMargin(top: 8, bottom: 8)
                }
                .link {
                    ForegroundColor(.accentColor)
                }
                .strong {
                    FontWeight(.semibold)
                }
                .heading1 { configuration in
                    configuration.label
                        .markdownTextStyle { FontSize(15); FontWeight(.bold) }
                        .markdownMargin(top: 12, bottom: 6)
                }
                .heading2 { configuration in
                    configuration.label
                        .markdownTextStyle { FontSize(14); FontWeight(.bold) }
                        .markdownMargin(top: 10, bottom: 5)
                }
                .heading3 { configuration in
                    configuration.label
                        .markdownTextStyle { FontSize(13.5); FontWeight(.semibold) }
                        .markdownMargin(top: 8, bottom: 4)
                }
                .listItem { configuration in
                    configuration.label
                        .markdownMargin(top: 3, bottom: 3)
                }
        }
    }
}

