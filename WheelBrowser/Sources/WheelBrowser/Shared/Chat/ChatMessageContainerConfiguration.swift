import SwiftUI

/// Configuration for chat message container appearance
public struct ChatMessageContainerConfiguration {
    /// Maximum width for user messages
    public var userMessageMaxWidth: CGFloat

    /// Whether to show role indicator labels
    public var showRoleIndicator: Bool

    /// Corner radius for message bubbles
    public var cornerRadius: CGFloat

    /// Horizontal padding inside bubbles
    public var horizontalPadding: CGFloat

    /// Vertical padding inside bubbles
    public var verticalPadding: CGFloat

    /// Spacing between messages
    public var messageSpacing: CGFloat

    public init(
        userMessageMaxWidth: CGFloat = 400,
        showRoleIndicator: Bool = true,
        cornerRadius: CGFloat = 12,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8,
        messageSpacing: CGFloat = 14
    ) {
        self.userMessageMaxWidth = userMessageMaxWidth
        self.showRoleIndicator = showRoleIndicator
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.messageSpacing = messageSpacing
    }

    /// Default configuration
    public static let standard = ChatMessageContainerConfiguration()

    /// Compact configuration for smaller UI contexts
    public static let compact = ChatMessageContainerConfiguration(
        userMessageMaxWidth: 300,
        showRoleIndicator: false,
        cornerRadius: 10,
        horizontalPadding: 10,
        verticalPadding: 6,
        messageSpacing: 10
    )
}
