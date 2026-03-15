import Testing
@testable import WheelBrowser

@Suite("OmniBar Tab Transition Policy Tests")
struct OmniBarTabTransitionPolicyTests {
    @Test("Blank tabs do not latch into full-page chat when chat is disabled")
    func blankTabDoesNotLatchIntoChat() {
        let tab = Tab()

        #expect(
            OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
                tab: tab,
                currentMode: .chat,
                isInputFocused: true,
                hasExplicitChatFocusIntent: false
            ) == false
        )
        #expect(
            OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
                tab: tab,
                currentMode: .chat,
                isInputFocused: false,
                hasExplicitChatFocusIntent: true
            ) == false
        )
        #expect(
            OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
                tab: tab,
                currentMode: .chat,
                isInputFocused: true,
                hasExplicitChatFocusIntent: true
            ) == false
        )
    }

    @Test("Chat reset policy stays off when chat is disabled")
    func freshBlankTabDoesNotResetToAddressMode() {
        let blankTab = Tab()
        let existingChatTab = Tab(isChatTab: true, hasConversationStarted: true)

        #expect(
            OmniBarTabTransitionPolicy.shouldResetToAddressMode(
                for: blankTab,
                currentMode: .chat
            ) == false
        )
        #expect(
            OmniBarTabTransitionPolicy.shouldResetToAddressMode(
                for: existingChatTab,
                currentMode: .chat
            ) == false
        )
        #expect(
            OmniBarTabTransitionPolicy.shouldResetToAddressMode(
                for: blankTab,
                currentMode: .semantic
            ) == false
        )
    }
}
