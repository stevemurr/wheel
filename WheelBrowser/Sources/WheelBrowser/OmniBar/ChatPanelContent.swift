import SwiftUI

// MARK: - Chat Panel using OmniPanel

struct ChatPanelContent: View {
    @ObservedObject var agentManager: AgentManager
    var onSubmitPrompt: ((String) -> Void)?
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
                VStack(spacing: 8) {
                    if agentManager.messages.isEmpty {
                        WelcomeStateView(compact: true) { prompt in
                            onSubmitPrompt?(prompt)
                        }
                        .padding(.top, 20)

                        if let error = agentManager.error {
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
                    } else {
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
                                        agentManager.selectedArtifact = artifact
                                    }
                                )

                                // Retry button for failed messages
                                if message.isFailed {
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
                            .id(message.id)
                        }

                        // Follow-up suggestions after last assistant message
                        if !followUpSuggestions.isEmpty {
                            FollowUpSuggestionsView(suggestions: followUpSuggestions) { suggestion in
                                onSubmitPrompt?(suggestion)
                            }
                            .padding(.top, 4)
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
                // Pin user question at top of viewport
                if let userID = latestUserMessageID {
                    withAnimation(AppAnimation.standard) {
                        proxy.scrollTo(userID, anchor: .top)
                    }
                }
            }
            .onChange(of: agentManager.messages.last?.content) { _, _ in
                // Throttled scroll during streaming (max once per 150ms)
                let now = Date()
                if now.timeIntervalSince(lastScrollTime) > 0.15 {
                    lastScrollTime = now
                    proxy.scrollToBottom(animated: false)
                }
            }
        }
    }

    var subtitle: String? {
        if agentManager.isLoading {
            return "Thinking..."
        }
        return nil
    }
}
