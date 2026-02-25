import SwiftUI

/// A reusable container view for rendering chat messages with role-based styling.
/// Provides consistent message bubble appearance across the application.
public struct ChatMessageContainerView<Content: View>: View {
    let message: ChatMessage
    let content: Content
    let configuration: ChatMessageContainerConfiguration

    public init(
        message: ChatMessage,
        configuration: ChatMessageContainerConfiguration = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.message = message
        self.configuration = configuration
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if configuration.showRoleIndicator && message.role == .user {
                    roleIndicator
                }

                content
                    .padding(.horizontal, configuration.horizontalPadding)
                    .padding(.vertical, configuration.verticalPadding)
                    .frame(minWidth: 60, alignment: message.role == .user ? .trailing : .leading)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                            .stroke(bubbleBorder, lineWidth: 0.5)
                    )
            }
            .frame(
                maxWidth: message.role == .user ? configuration.userMessageMaxWidth : .infinity,
                alignment: message.role == .user ? .trailing : .leading
            )

            if message.role != .user {
                Spacer(minLength: 50)
            }
        }
        .padding(.vertical, 2)
        .id(message.id)
    }

    private var roleIndicator: some View {
        HStack(spacing: 4) {
            Text("You")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
            Image(systemName: "person.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.6))
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
}

// MARK: - Text Styling Helpers

extension ChatMessageContainerView {
    /// Get the appropriate text color for the current message role
    public var textColor: Color {
        switch message.role {
        case .user:
            return .white
        case .assistant, .system, .thinking:
            return .primary
        }
    }
}

// MARK: - Convenience Initializer for Text Content

extension ChatMessageContainerView where Content == Text {
    /// Create a message container with simple text content
    public init(message: ChatMessage, configuration: ChatMessageContainerConfiguration = .standard) {
        self.message = message
        self.configuration = configuration
        self.content = Text(message.content)
            .font(.system(size: 13))
            .foregroundColor(message.role == .user ? .white : .primary)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct ChatMessageContainerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 14) {
            ChatMessageContainerView(message: .user("Hello, how can you help me?"))

            ChatMessageContainerView(message: .assistant("I can help you with many things!"))

            ChatMessageContainerView(message: .system("System notification here"))

            ChatMessageContainerView(message: .thinking("Let me think about this..."))
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
