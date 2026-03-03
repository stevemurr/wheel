import SwiftUI

/// Full-page chat view shown on empty tabs when chat mode is active.
/// Replaces `NewTabPageView` with a centered message thread or empty state.
struct FullPageChatView: View {
    @ObservedObject var agentManager: AgentManager
    var onSubmitPrompt: ((String) -> Void)?
    @State private var lastScrollTime: Date = .distantPast
    @State private var selectedArtifact: ChatArtifact?

    private var latestUserMessageID: UUID? {
        agentManager.messages.last(where: { $0.role == .user })?.id
    }

    /// Follow-up suggestions from the last assistant message
    private var followUpSuggestions: [String] {
        guard !agentManager.isStreamingActive,
              let lastAssistant = agentManager.messages.last(where: { $0.role == .assistant }) else {
            return []
        }
        return lastAssistant.suggestedFollowUps
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main chat column
            chatColumn
                .frame(maxWidth: selectedArtifact != nil ? 400 : .infinity)

            // Artifact panel (slides in from right)
            if let artifact = selectedArtifact {
                Divider()
                VStack(spacing: 0) {
                    ArtifactPanelView(artifact: artifact) {
                        withAnimation(AppAnimation.standard) {
                            selectedArtifact = nil
                        }
                    }
                    .frame(maxHeight: WindowConstants.maxPanelHeight)
                    .clipShape(RoundedRectangle(cornerRadius: WindowConstants.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WindowConstants.cardCornerRadius, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 12)
                    .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(minWidth: 350, maxWidth: 600)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .animation(AppAnimation.standard, value: selectedArtifact != nil)
    }

    // MARK: - Chat Column

    private var chatColumn: some View {
        Group {
            if agentManager.messages.isEmpty {
                WelcomeStateView(compact: false) { prompt in
                    onSubmitPrompt?(prompt)
                }
            } else {
                messageList
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(Array(agentManager.messages.enumerated()), id: \.element.id) { index, message in
                        VStack(alignment: .leading, spacing: 4) {
                            ChatPanelMessageBubble(
                                message: message,
                                onEdit: { newContent in
                                    Task {
                                        await agentManager.editAndResend(
                                            messageIndex: index,
                                            newContent: newContent,
                                            pageContexts: []
                                        )
                                    }
                                },
                                onRegenerate: {
                                    Task {
                                        await agentManager.regenerateResponse(at: index)
                                    }
                                },
                                onSelectArtifact: { artifact in
                                    withAnimation(AppAnimation.standard) {
                                        selectedArtifact = artifact
                                    }
                                }
                            )

                            if message.isFailed {
                                retryButton
                            }
                        }
                        .id(message.id)
                    }

                    // Follow-up suggestions
                    if !followUpSuggestions.isEmpty {
                        FollowUpSuggestionsView(suggestions: followUpSuggestions) { suggestion in
                            onSubmitPrompt?(suggestion)
                        }
                        .padding(.top, 4)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 80)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: agentManager.messages.count) { _, _ in
                if let userID = latestUserMessageID {
                    withAnimation(AppAnimation.standard) {
                        proxy.scrollTo(userID, anchor: .top)
                    }
                }
            }
            .onChange(of: agentManager.messages.last?.content) { _, _ in
                let now = Date()
                if now.timeIntervalSince(lastScrollTime) > 0.15 {
                    lastScrollTime = now
                    proxy.scrollToBottom(animated: false)
                }
            }
        }
    }

    // MARK: - Retry Button

    private var retryButton: some View {
        Button(action: {
            Task {
                await agentManager.retryLastFailedMessage()
            }
        }) {
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
