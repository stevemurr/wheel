import Foundation

enum OmniBarTabTransitionPolicy {
    static func shouldResetToAddressMode(for tab: Tab, currentMode: OmniBarMode) -> Bool {
        currentMode == .chat && shouldPreferNewTabPage(for: tab)
    }

    static func shouldLatchEmptyTabIntoChat(
        tab: Tab,
        currentMode: OmniBarMode,
        isInputFocused: Bool,
        hasExplicitChatFocusIntent: Bool
    ) -> Bool {
        shouldPreferNewTabPage(for: tab)
            && currentMode == .chat
            && isInputFocused
            && hasExplicitChatFocusIntent
    }

    private static func shouldPreferNewTabPage(for tab: Tab) -> Bool {
        tab.url == nil && !tab.isChatTab && !tab.hasConversationStarted
    }
}
