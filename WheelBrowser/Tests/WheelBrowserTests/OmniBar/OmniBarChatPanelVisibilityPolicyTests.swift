import Testing
@testable import WheelBrowser

@Suite("OmniBar Chat Panel Visibility Policy Tests")
struct OmniBarChatPanelVisibilityPolicyTests {
    @Test("Chat panel stays visible during the local send window")
    func keepsPanelVisibleWhileSending() {
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowPanel(
                isSending: true,
                isLoading: false,
                isStreaming: false,
                hasMessages: false
            )
        )
    }

    @Test("Chat panel stays visible for active or populated conversations")
    func keepsPanelVisibleForActiveConversationState() {
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowPanel(
                isSending: false,
                isLoading: true,
                isStreaming: false,
                hasMessages: false
            )
        )
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowPanel(
                isSending: false,
                isLoading: false,
                isStreaming: true,
                hasMessages: false
            )
        )
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowPanel(
                isSending: false,
                isLoading: false,
                isStreaming: false,
                hasMessages: true
            )
        )
    }

    @Test("Chat panel hides when conversation is idle and empty")
    func hidesPanelForIdleEmptyState() {
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowPanel(
                isSending: false,
                isLoading: false,
                isStreaming: false,
                hasMessages: false
            ) == false
        )
    }

    @Test("Floating chat panel stays suppressed while full-page chat owns the surface")
    func suppressesFloatingPanelForFullPageChat() {
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowFloatingPanel(
                isSending: true,
                isLoading: false,
                isStreaming: false,
                hasMessages: false,
                isFullPageChatActiveOrPending: true
            ) == false
        )
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowFloatingPanel(
                isSending: false,
                isLoading: false,
                isStreaming: false,
                hasMessages: true,
                isFullPageChatActiveOrPending: true
            ) == false
        )
    }

    @Test("Floating chat panel remains available for non-full-page chat surfaces")
    func allowsFloatingPanelOutsideFullPageChat() {
        #expect(
            OmniBarChatPanelVisibilityPolicy.shouldShowFloatingPanel(
                isSending: false,
                isLoading: false,
                isStreaming: true,
                hasMessages: false,
                isFullPageChatActiveOrPending: false
            )
        )
    }
}
