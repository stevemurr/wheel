enum OmniBarChatPanelVisibilityPolicy {
    static func shouldShowPanel(
        isSending: Bool,
        isLoading: Bool,
        isStreaming: Bool,
        hasMessages: Bool
    ) -> Bool {
        isSending || isLoading || isStreaming || hasMessages
    }

    static func shouldShowFloatingPanel(
        isSending: Bool,
        isLoading: Bool,
        isStreaming: Bool,
        hasMessages: Bool,
        isFullPageChatActiveOrPending: Bool
    ) -> Bool {
        guard !isFullPageChatActiveOrPending else { return false }
        return shouldShowPanel(
            isSending: isSending,
            isLoading: isLoading,
            isStreaming: isStreaming,
            hasMessages: hasMessages
        )
    }
}
