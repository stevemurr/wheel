import SwiftUI
import MarkdownUI
import AppKit

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

/// Collapsible thinking/reasoning bubble for displaying AI thought process
struct ThinkingBubble: View {
    let message: ChatMessage
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.purple.opacity(0.7))
                        .frame(width: 12)

                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple.opacity(0.7))

                    Text("Thinking")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.purple.opacity(0.8))

                    if message.isStreaming {
                        ChatPanelPulsingDot()
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    Text("\(message.content.count) chars")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }

            // Expandable content
            if isExpanded {
                Divider()
                    .opacity(0.3)

                ScrollView {
                    Text(message.content)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.75))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.purple.opacity(isHovered ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact message bubble for the chat panel
struct ChatPanelMessageBubble: View {
    let message: ChatMessage
    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        // Special handling for thinking messages - use collapsible view
        if message.role == .thinking {
            ThinkingBubble(message: message)
                .padding(.vertical, 2)
        } else {
            regularMessageBubble
        }
    }

    private var regularMessageBubble: some View {
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
                    } else {
                        // Render full markdown
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
                        .stroke(bubbleBorder, lineWidth: 1.0)
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
        PasteboardHelper.copy(message.content)
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopied = false
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.accentColor
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
                // Stylish table rendering with native macOS appearance
                .table { configuration in
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .markdownTableBorderStyle(
                            TableBorderStyle(
                                .allBorders,
                                color: Color(nsColor: .separatorColor).opacity(0.4),
                                width: 1
                            )
                        )
                        .markdownTableBackgroundStyle(
                            .alternatingRows(
                                Color(nsColor: .controlBackgroundColor).opacity(0.3),
                                Color.clear,
                                header: Color(nsColor: .controlBackgroundColor).opacity(0.6)
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
                        )
                        .markdownMargin(top: 8, bottom: 12)
                }
                .tableCell { configuration in
                    configuration.label
                        .markdownTextStyle {
                            if configuration.row == 0 {
                                FontWeight(.semibold)
                            }
                            FontSize(12.5)
                            BackgroundColor(nil)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
        }
    }
}

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
