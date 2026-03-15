import SwiftUI
import MarkdownUI
import AppKit

private enum ChatSurfaceStyle {
    static func userFill(compact: Bool) -> Color {
        Color.accentColor.opacity(compact ? 0.14 : 0.10)
    }

    static func userBorder(compact: Bool) -> Color {
        Color.accentColor.opacity(compact ? 0.24 : 0.18)
    }

    static func assistantFill(compact: Bool) -> Color {
        compact
            ? Color(nsColor: .controlBackgroundColor).opacity(0.72)
            : .clear
    }

    static func assistantBorder(compact: Bool) -> Color {
        compact
            ? Color(nsColor: .separatorColor).opacity(0.22)
            : .clear
    }
}

/// Collapsible thinking/reasoning bubble for displaying AI thought process
struct ThinkingBubble: View {
    let message: ChatMessage
    var compact: Bool = false
    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(message: ChatMessage, compact: Bool = false) {
        self.message = message
        self.compact = compact
        let hasDetails = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self._isExpanded = State(initialValue: message.isStreaming && hasDetails)
    }

    private var hasDetails: Bool {
        message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            .onHover { hovering in
                isHovered = hovering
            }
            .onChange(of: message.isStreaming) { _, newValue in
                if !newValue && isExpanded {
                    withAnimation(AppAnimation.medium) {
                        isExpanded = false
                    }
                }
            }
            .onChange(of: message.content) { _, newValue in
                let hasContent = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                if hasContent && message.isStreaming && !isExpanded {
                    withAnimation(AppAnimation.medium) {
                        isExpanded = true
                    }
                }
            }

            if hasDetails && isExpanded {
                Divider()
                    .opacity(0.3)

                ThinkingContentView(content: message.content, compact: compact)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .bottomLeading) {
            if message.isStreaming {
                ThinkingProgressSweep(compact: compact)
                    .padding(.horizontal, compact ? 12 : 14)
                    .padding(.bottom, 1)
            }
        }
        .shadow(
            color: Color.black.opacity(compact ? 0.04 : 0.06),
            radius: compact ? 4 : 8,
            x: 0,
            y: compact ? 1 : 3
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var header: some View {
        if hasDetails {
            Button(action: toggleExpanded) {
                headerContent
            }
            .buttonStyle(.plain)
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack(spacing: compact ? 8 : 10) {
            thinkingIcon

            HStack(spacing: 4) {
                Text("Thought Process")
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
                    .foregroundColor(.primary.opacity(0.78))

                Image(systemName: hasDetails && isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if let duration = message.thinkingDurationSeconds,
                   duration >= 1,
                   !message.isStreaming {
                    Text(durationLabel(for: duration))
                        .font(.system(size: compact ? 10 : 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.62))
                }

                if message.isStreaming {
                    ThinkingActivityIndicator(compact: compact)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.15, green: 0.73, blue: 0.45))
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 9)
        .contentShape(Rectangle())
    }

    private var thinkingIcon: some View {
        RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.08, blue: 0.12),
                        Color(red: 0.26, green: 0.07, blue: 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.69, blue: 0.34),
                                Color(red: 0.95, green: 0.28, blue: 0.30),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var backgroundFill: LinearGradient {
        let topOpacity = isHovered ? 0.95 : 0.90
        let bottomOpacity = isHovered ? 0.90 : 0.82
        return LinearGradient(
            colors: [
                Color(nsColor: .textBackgroundColor).opacity(topOpacity),
                Color(nsColor: .controlBackgroundColor).opacity(bottomOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        if message.isStreaming {
            return Color(red: 0.92, green: 0.38, blue: 0.31).opacity(0.34)
        }
        return Color(nsColor: .separatorColor).opacity(0.26)
    }

    private func toggleExpanded() {
        withAnimation(AppAnimation.medium) {
            isExpanded.toggle()
        }
    }

    private func durationLabel(for duration: TimeInterval) -> String {
        let rounded = max(1, Int(duration.rounded(.up)))
        return "\(rounded)s"
    }
}

/// Extracted content view for ThinkingBubble — isolates text rendering from header (timer, progress bar)
private struct ThinkingContentView: View {
    let content: String
    let compact: Bool

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(size: compact ? 11.5 : 12.5, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.88))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
        }
        .frame(maxHeight: compact ? 180 : 220)
    }
}

private struct ThinkingActivityIndicator: View {
    let compact: Bool
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.10), lineWidth: 1.2)

            Circle()
                .trim(from: 0.10, to: 0.62)
                .stroke(
                    Color(red: 0.94, green: 0.37, blue: 0.30),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct ThinkingProgressSweep: View {
    let compact: Bool
    @State private var offset: CGFloat = -0.35

    var body: some View {
        GeometryReader { geometry in
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.06))
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(red: 0.99, green: 0.68, blue: 0.33).opacity(0.95),
                                    Color(red: 0.94, green: 0.36, blue: 0.29).opacity(0.95),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geometry.size.width * 0.24, compact ? 36 : 52))
                        .offset(x: offset * geometry.size.width)
                }
        }
        .frame(height: 2)
        .clipShape(Capsule(style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: false)) {
                offset = 1.1
            }
        }
    }
}

// MARK: - Isolated Sub-Views for Streaming Performance

/// Renders only the Markdown content + streaming cursor.
/// Isolated so that content changes during streaming don't re-evaluate siblings (artifacts, action bar).
private struct MessageContentView: View {
    let content: String
    let role: ChatMessage.MessageRole
    let isStreaming: Bool
    let compact: Bool

    private var renderableContent: String {
        ChatMarkdownFormatter.renderableContent(content, closeUnbalancedFence: true)
    }

    var body: some View {
        Markdown(renderableContent)
            .markdownTheme(ChatMarkdownTheme.theme(for: role, compact: compact))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

        if isStreaming && !content.isEmpty {
            StreamingCursor()
        }
    }
}

/// Renders artifact chips. Artifacts don't change during streaming, so this sub-view
/// won't re-evaluate while content is being appended.
private struct ArtifactChipsView: View {
    let artifacts: [ChatArtifact]
    var onSelectArtifact: ((ChatArtifact) -> Void)?

    var body: some View {
        if !artifacts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(artifacts) { artifact in
                        ArtifactChip(artifact: artifact) {
                            onSelectArtifact?(artifact)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

/// Compact message bubble for the chat panel
struct ChatPanelMessageBubble: View {
    let message: ChatMessage
    var compact: Bool = false
    var onEdit: ((String) -> Void)?
    var onRegenerate: (() -> Void)?
    var onSelectArtifact: ((ChatArtifact) -> Void)?
    @State private var isEditing = false

    var body: some View {
        // Special handling for thinking messages - use collapsible view
        if message.role == .thinking {
            ThinkingBubble(message: message, compact: compact)
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
                    userHeader
                }

                // Inline editor or message content
                if isEditing && message.role == .user {
                    InlineMessageEditor(
                        originalContent: message.content,
                        onSave: { newContent in
                            isEditing = false
                            onEdit?(newContent)
                        },
                        onCancel: { isEditing = false }
                    )
                } else {
                    // Message content — sub-views isolate Markdown from artifacts
                    Group {
                        if message.content.isEmpty && message.isStreaming {
                            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                                if message.role == .assistant, let contextBadges = message.contextBadges {
                                    ChatContextBadgeRow(
                                        badges: contextBadges,
                                        compact: compact
                                    )
                                }

                                ChatPanelTypingIndicator()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        } else {
                            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                                if message.role == .assistant, let contextBadges = message.contextBadges {
                                    ChatContextBadgeRow(
                                        badges: contextBadges,
                                        compact: compact
                                    )
                                }

                                MessageContentView(
                                    content: message.content,
                                    role: message.role,
                                    isStreaming: message.isStreaming,
                                    compact: compact
                                )

                                // Artifact chips (isolated — won't re-eval during streaming)
                                if message.role == .assistant {
                                    ArtifactChipsView(
                                        artifacts: message.artifacts,
                                        onSelectArtifact: onSelectArtifact
                                    )
                                }
                            }
                            .padding(.horizontal, contentHorizontalPadding)
                            .padding(.vertical, contentVerticalPadding)
                        }
                    }
                    .frame(minWidth: 60, alignment: message.role == .user ? .trailing : .leading)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                            .stroke(bubbleBorder, lineWidth: 1.0)
                    )
                }

                // Action bar — guarded behind !isStreaming so it won't re-eval during streaming
                if !message.isStreaming && !message.content.isEmpty && !isEditing {
                    MessageActionBar(
                        message: message,
                        leadingInset: message.role == .assistant ? actionBarLeadingInset : 0,
                        trailingInset: message.role == .user ? actionBarTrailingInset : 0,
                        onEdit: message.role == .user ? { isEditing = true } : nil,
                        onRegenerate: message.role == .assistant ? onRegenerate : nil
                    )
                }
            }
            .frame(maxWidth: message.role == .user ? userBubbleMaxWidth : .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user {
                Spacer(minLength: 50)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            ChatSurfaceStyle.userFill(compact: compact)
        case .assistant:
            ChatSurfaceStyle.assistantFill(compact: compact)
        case .system:
            Color.orange.opacity(compact ? 0.10 : 0.08)
        case .thinking:
            Color.purple.opacity(0.08)
        }
    }

    private var bubbleBorder: Color {
        switch message.role {
        case .user:
            return ChatSurfaceStyle.userBorder(compact: compact)
        case .assistant:
            return ChatSurfaceStyle.assistantBorder(compact: compact)
        case .system:
            return Color.orange.opacity(0.2)
        case .thinking:
            return Color.purple.opacity(0.15)
        }
    }

    private var userBubbleMaxWidth: CGFloat {
        compact ? 360 : 520
    }

    private var bubbleCornerRadius: CGFloat {
        compact ? 14 : 18
    }

    private var contentHorizontalPadding: CGFloat {
        if message.role == .assistant && !compact {
            return 4
        }
        return compact ? 12 : 14
    }

    private var contentVerticalPadding: CGFloat {
        if message.role == .assistant && !compact {
            return 2
        }
        return compact ? 12 : 13
    }

    private var actionBarLeadingInset: CGFloat {
        compact ? contentHorizontalPadding : max(6, contentHorizontalPadding)
    }

    private var actionBarTrailingInset: CGFloat {
        compact ? contentHorizontalPadding : max(8, contentHorizontalPadding)
    }

    private var userHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.accentColor.opacity(0.82))
                }

            Text("You")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

}

/// Blinking cursor shown at the end of streaming content (Rule 5 compliant)
private struct StreamingCursor: View {
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.purple)
            .frame(width: 2, height: 14)
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
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
