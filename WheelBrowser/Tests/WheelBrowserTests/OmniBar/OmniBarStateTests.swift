import Testing
@testable import WheelBrowser

@MainActor
@Suite("OmniBar State")
struct OmniBarStateTests {
    @Test("User removal of auto page context is preserved across mention resets")
    func userRemovalSuppressesAutomaticPageContext() {
        OverlayWindowManager.shared.closeAll()

        let state = OmniBarState()
        state.resetMentions(includeCurrentPage: true)
        #expect(state.mentions.contains(.currentPage))

        state.removeMention(.currentPage)
        state.resetMentions(includeCurrentPage: true)

        #expect(state.mentions.contains(.currentPage) == false)
    }

    @Test("System removal does not suppress automatic page context")
    func systemRemovalDoesNotSuppressAutomaticPageContext() {
        OverlayWindowManager.shared.closeAll()

        let state = OmniBarState()
        state.resetMentions(includeCurrentPage: true)
        state.removeMention(.currentPage, userInitiated: false)
        state.resetMentions(includeCurrentPage: true)

        #expect(state.mentions.contains(.currentPage))
    }

    @Test("Clearing suppression restores automatic page context")
    func clearingSuppressionRestoresAutomaticPageContext() {
        OverlayWindowManager.shared.closeAll()

        let state = OmniBarState()
        state.removeMention(.currentPage)
        state.resetMentions(includeCurrentPage: true)
        #expect(state.mentions.contains(.currentPage) == false)

        state.clearAutomaticMentionSuppression()
        state.resetMentions(includeCurrentPage: true)

        #expect(state.mentions.contains(.currentPage))
    }

    @Test("Manually re-adding the page mention clears suppression")
    func reAddingMentionClearsSuppression() {
        OverlayWindowManager.shared.closeAll()

        let state = OmniBarState()
        state.removeMention(.currentPage)
        state.resetMentions(includeCurrentPage: true)
        #expect(state.mentions.contains(.currentPage) == false)

        state.addMention(.currentPage)
        state.resetMentions(includeCurrentPage: true)

        #expect(state.mentions.contains(.currentPage))
    }
}
