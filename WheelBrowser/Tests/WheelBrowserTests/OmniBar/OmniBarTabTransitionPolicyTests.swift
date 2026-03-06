import Testing
@testable import WheelBrowser

@Suite("OmniBar Tab Transition Policy Tests")
struct OmniBarTabTransitionPolicyTests {
    @Test("Blank tabs only latch into full-page chat when chat was actively focused")
    func blankTabDoesNotLatchIntoChatWithoutFocus() {
        let tab = Tab()

        #expect(
            OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
                tab: tab,
                currentMode: .chat,
                isInputFocused: false
            ) == false
        )
        #expect(
            OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
                tab: tab,
                currentMode: .chat,
                isInputFocused: true
            ) == true
        )
    }

    @Test("Fresh blank tabs reset out of leaked chat mode")
    func freshBlankTabResetsToAddressMode() {
        let blankTab = Tab()
        let existingChatTab = Tab(isChatTab: true, hasConversationStarted: true)

        #expect(
            OmniBarTabTransitionPolicy.shouldResetToAddressMode(
                for: blankTab,
                currentMode: .chat
            )
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
