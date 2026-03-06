enum OmniBarChatPanelVisibilityPolicy {
    static func shouldShowPanel(
        isSending: Bool,
        isLoading: Bool,
        isStreaming: Bool,
        hasMessages: Bool
    ) -> Bool {
        isSending || isLoading || isStreaming || hasMessages
    }
}
