import SwiftUI

// MARK: - Chat Panel using OmniPanel

struct ChatPanelContent: View {
    @ObservedObject var agentManager: AgentManager
    @State private var lastScrollTime: Date = .distantPast

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(spacing: 8) {
                    if agentManager.messages.isEmpty {
                        OmniPanelEmptyState(
                            icon: "bubble.left.and.bubble.right",
                            title: "Start a conversation",
                            subtitle: "Ask questions about the current page"
                        )
                        .padding(.top, 30)

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
                        ForEach(agentManager.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                ChatPanelMessageBubble(message: message)

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
                proxy.scrollToBottom(animated: true)
            }
            .onChange(of: agentManager.messages.last?.content) { _, _ in
                // Throttled scroll during streaming (max once per 100ms)
                let now = Date()
                if now.timeIntervalSince(lastScrollTime) > 0.1 {
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
