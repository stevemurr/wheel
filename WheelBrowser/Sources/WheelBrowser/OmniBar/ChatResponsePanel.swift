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
    var compact: Bool = false
    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(message: ChatMessage, compact: Bool = false) {
        self.message = message
        self.compact = compact
        // Auto-expand while streaming
        self._isExpanded = State(initialValue: message.isStreaming)
    }

    /// Duration label: shows "Thought for Xs" or live timer during streaming
    private var durationLabel: String {
        if let duration = message.thinkingDurationSeconds {
            return "Thought for \(Int(duration))s"
        }
        return "\(message.content.count) chars"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with toggle
            Button(action: {
                withAnimation(AppAnimation.medium) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.85))
                        .frame(width: 12)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(nsColor: .controlAccentColor).opacity(0.8))
                        }

                    Text("Thought Process")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.82))

                    if message.isStreaming {
                        // Live timer using TimelineView (Rule 5: no .contentTransition on streaming)
                        if let startTime = message.thinkingStartTime {
                            ThinkingLiveTimer(startTime: startTime)
                        } else {
                            ChatPanelPulsingDot()
                                .scaleEffect(0.7)
                        }

                        // Subtle indeterminate progress bar
                        ThinkingProgressBar()
                            .frame(width: 40, height: 2)
                    }

                    Spacer()

                    if !message.isStreaming {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green.opacity(0.72))
                    }

                    Text(durationLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.65))
                }
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            // Auto-collapse when streaming ends
            .onChange(of: message.isStreaming) { _, newValue in
                if !newValue && isExpanded {
                    withAnimation(AppAnimation.medium) {
                        isExpanded = false
                    }
                }
            }

            // Expandable content — extracted so header doesn't force content re-render
            if isExpanded {
                Divider()
                    .opacity(0.3)

                ThinkingContentView(content: message.content, compact: compact)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.82 : 0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Live timer that updates every second during thinking (Rule 5 compliant - no contentTransition)
private struct ThinkingLiveTimer: View {
    let startTime: Date

    var body: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { timeline in
            let elapsed = Int(timeline.date.timeIntervalSince(startTime))
            Text("\(elapsed)s")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

/// Subtle indeterminate progress bar for thinking state
private struct ThinkingProgressBar: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(nsColor: .controlAccentColor).opacity(0.35))
                .frame(width: geometry.size.width * 0.4)
                .offset(x: offset * geometry.size.width * 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .background(Color(nsColor: .separatorColor).opacity(0.18))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                offset = 1
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

    var body: some View {
        Markdown(content)
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
                            ChatPanelTypingIndicator()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
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
