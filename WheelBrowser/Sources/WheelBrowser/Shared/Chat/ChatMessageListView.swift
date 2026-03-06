import SwiftUI

/// Shared message list used by both `ChatPanelContent` (OmniBar panel) and `FullPageChatView`.
/// Uses `LazyVStack` so off-screen messages aren't instantiated, and `ForEach` keyed on
/// stable message IDs (not positional indices) so streaming insertions don't invalidate the list.
struct ChatMessageListView: View {
    var agentManager: AgentManager  // @Observable — per-property tracking, no @ObservedObject needed
    var onSubmitPrompt: ((String) -> Void)?
    var onSelectArtifact: ((ChatArtifact) -> Void)?
    /// Whether to use compact styling (OmniBar panel) vs full-page styling
    var compact: Bool

    @State private var lastScrollTime: Date = .distantPast

    private var latestUserMessageID: UUID? {
        agentManager.messages.last(where: { $0.role == .user })?.id
    }

    /// Follow-up suggestions from the last assistant message (when not streaming)
    private var followUpSuggestions: [String] {
        guard !agentManager.isStreamingActive,
              let lastAssistant = agentManager.messages.last(where: { $0.role == .assistant }) else {
            return []
        }
        return lastAssistant.suggestedFollowUps
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: compact ? 10 : 18) {
                    if agentManager.messages.isEmpty {
                        emptyState
                    } else {
                        messageRows
                        followUps
                        scrollAnchor
                    }
                }
                .padding(.horizontal, compact ? 14 : 28)
                .padding(.top, compact ? 12 : 28)
                .padding(.bottom, compact ? 12 : 96)
                .if(!compact) { view in
                    view.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
            .onChange(of: agentManager.messages.count) { _, _ in
                if let userID = latestUserMessageID {
                    withAnimation(AppAnimation.standard) {
                        proxy.scrollTo(userID, anchor: .top)
                    }
                }
            }
            .onChange(of: agentManager.streamingScrollToken) { _, _ in
                let now = Date()
                if now.timeIntervalSince(lastScrollTime) > WindowConstants.streamingScrollThrottle {
                    lastScrollTime = now
                    proxy.scrollToBottom(animated: false)
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        WelcomeStateView(compact: compact) { prompt in
            onSubmitPrompt?(prompt)
        }
        .padding(.top, compact ? 20 : 0)

        if compact, let error = agentManager.error {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
                .multilineTextAlignment(.center)

            Button("Retry") {
                agentManager.error = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Message Rows

    private var messageRows: some View {
        ForEach(agentManager.messages) { message in
            VStack(alignment: .leading, spacing: 4) {
                ChatPanelMessageBubble(
                    message: message,
                    compact: compact,
                    onEdit: { newContent in
                        Task {
                            await agentManager.editAndResend(
                                messageID: message.id,
                                newContent: newContent,
                                pageContexts: []
                            )
                        }
                    },
                    onRegenerate: {
                        Task {
                            await agentManager.regenerateResponse(messageID: message.id)
                        }
                    },
                    onSelectArtifact: { artifact in
                        onSelectArtifact?(artifact)
                    }
                )

                if message.isFailed {
                    RetryButton {
                        Task {
                            await agentManager.retryLastFailedMessage()
                        }
                    }
                }
            }
            .id(message.id)
        }
    }

    // MARK: - Follow-ups & Anchor

    @ViewBuilder
    private var followUps: some View {
        if !followUpSuggestions.isEmpty {
            FollowUpSuggestionsView(suggestions: followUpSuggestions) { suggestion in
                onSubmitPrompt?(suggestion)
            }
            .padding(.top, 4)
        }
    }

    private var scrollAnchor: some View {
        Color.clear
            .frame(height: 1)
            .id("bottom")
    }
}

// MARK: - Retry Button (shared)

private struct RetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                Text("Retry")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conditional modifier helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
