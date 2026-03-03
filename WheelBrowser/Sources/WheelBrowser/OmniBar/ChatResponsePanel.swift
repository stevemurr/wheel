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
    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(message: ChatMessage) {
        self.message = message
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
                        .foregroundColor(.purple.opacity(0.7))
                        .frame(width: 12)

                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple.opacity(0.7))

                    Text("Thinking")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.purple.opacity(0.8))

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

                    Text(durationLabel)
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

                ThinkingContentView(content: message.content)
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

/// Extracted content view for ThinkingBubble — isolates text rendering from header (timer, progress bar)
private struct ThinkingContentView: View {
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
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

/// Live timer that updates every second during thinking (Rule 5 compliant - no contentTransition)
private struct ThinkingLiveTimer: View {
    let startTime: Date

    var body: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { timeline in
            let elapsed = Int(timeline.date.timeIntervalSince(startTime))
            Text("\(elapsed)s")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.purple.opacity(0.6))
        }
    }
}

/// Subtle indeterminate progress bar for thinking state
private struct ThinkingProgressBar: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.purple.opacity(0.3))
                .frame(width: geometry.size.width * 0.4)
                .offset(x: offset * geometry.size.width * 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .background(Color.purple.opacity(0.1))
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

    var body: some View {
        Markdown(content)
            .markdownTheme(ChatMarkdownTheme.theme(for: role))
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
    var onEdit: ((String) -> Void)?
    var onRegenerate: (() -> Void)?
    var onSelectArtifact: ((ChatArtifact) -> Void)?
    @State private var isHovered = false
    @State private var isEditing = false

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
                                    isStreaming: message.isStreaming
                                )

                                // Artifact chips (isolated — won't re-eval during streaming)
                                if message.role == .assistant {
                                    ArtifactChipsView(
                                        artifacts: message.artifacts,
                                        onSelectArtifact: onSelectArtifact
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                        }
                    }
                    .frame(minWidth: 60, alignment: message.role == .user ? .trailing : .leading)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(bubbleBorder, lineWidth: 1.0)
                    )
                }

                // Hover action bar — guarded behind !isStreaming so it won't re-eval during streaming
                if !message.isStreaming && !message.content.isEmpty && !isEditing {
                    MessageActionBar(
                        message: message,
                        isHovered: isHovered,
                        onEdit: message.role == .user ? { isEditing = true } : nil,
                        onCopy: { PasteboardHelper.copy(message.content) },
                        onRegenerate: message.role == .assistant ? onRegenerate : nil
                    )
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
