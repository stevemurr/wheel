import SwiftUI

/// Full-page chat view shown on empty tabs when chat mode is active.
/// Replaces `NewTabPageView` with a centered message thread or empty state.
struct FullPageChatView: View {
    @ObservedObject var agentManager: AgentManager
    @State private var lastScrollTime: Date = .distantPast

    private var latestUserMessageID: UUID? {
        agentManager.messages.last(where: { $0.role == .user })?.id
    }

    var body: some View {
        Group {
            if agentManager.messages.isEmpty {
                emptyState
            } else {
                messageList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.purple.opacity(0.6))

            Text("What can I help you with?")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Type in the bar below to start a conversation")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(agentManager.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            ChatPanelMessageBubble(message: message)

                            if message.isFailed {
                                retryButton
                            }
                        }
                        .id(message.id)
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
