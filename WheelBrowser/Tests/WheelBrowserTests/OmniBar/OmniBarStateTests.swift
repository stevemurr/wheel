import Testing
@testable import WheelBrowser

@MainActor
@Suite("OmniBar Feature Model")
struct OmniBarStateTests {
    private func makeFeatureModel(tab: Tab = Tab()) -> OmniBarFeatureModel {
        let browserState = BrowserState()
        let agentManager = AgentManager()
        let agentEngine = AgentEngine(browserState: browserState, settings: AppSettings.shared)

        return OmniBarFeatureModel(
            tab: tab,
            agentManager: agentManager,
            browserState: browserState,
            fabricClient: nil,
            agentEngine: agentEngine,
            contentExtractor: ContentExtractor()
        )
    }

    @Test("User removal of auto page context is preserved across mention resets")
    func userRemovalSuppressesAutomaticPageContext() {
        OverlayWindowManager.shared.closeAll()

        let featureModel = makeFeatureModel()
        featureModel.resetMentions(includeCurrentPage: true)
        #expect(featureModel.mentions.contains(.currentPage))

        featureModel.removeMention(.currentPage)
        featureModel.resetMentions(includeCurrentPage: true)

        #expect(featureModel.mentions.contains(.currentPage) == false)
    }

    @Test("System removal does not suppress automatic page context")
    func systemRemovalDoesNotSuppressAutomaticPageContext() {
        OverlayWindowManager.shared.closeAll()

        let featureModel = makeFeatureModel()
        featureModel.resetMentions(includeCurrentPage: true)
        featureModel.removeMention(.currentPage, userInitiated: false)
        featureModel.resetMentions(includeCurrentPage: true)

        #expect(featureModel.mentions.contains(.currentPage))
    }

    @Test("Clearing suppression restores automatic page context")
    func clearingSuppressionRestoresAutomaticPageContext() {
        OverlayWindowManager.shared.closeAll()

        let featureModel = makeFeatureModel()
        featureModel.removeMention(.currentPage)
        featureModel.resetMentions(includeCurrentPage: true)
        #expect(featureModel.mentions.contains(.currentPage) == false)

        featureModel.clearAutomaticMentionSuppression()
        featureModel.resetMentions(includeCurrentPage: true)

        #expect(featureModel.mentions.contains(.currentPage))
    }

    @Test("Manually re-adding the page mention clears suppression")
    func reAddingMentionClearsSuppression() {
        OverlayWindowManager.shared.closeAll()

        let featureModel = makeFeatureModel()
        featureModel.removeMention(.currentPage)
        featureModel.resetMentions(includeCurrentPage: true)
        #expect(featureModel.mentions.contains(.currentPage) == false)

        featureModel.addMention(.currentPage)
        featureModel.resetMentions(includeCurrentPage: true)

        #expect(featureModel.mentions.contains(.currentPage))
    }

    @Test("Tab trapping stays active while any OmniBar surface is active")
    func tabTrappingActivatesForFocusedInputOrPanels() {
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: true,
                visiblePanel: .none,
                showMentionDropdown: false
            )
        )
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: false,
                visiblePanel: .semantic,
                showMentionDropdown: false
            )
        )
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: false,
                visiblePanel: .none,
                showMentionDropdown: true
            )
        )
    }

    @Test("Tab trapping stays off when the OmniBar is fully inactive")
    func tabTrappingStaysOffWhenOmniBarIsInactive() {
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: false,
                visiblePanel: .none,
                showMentionDropdown: false
            ) == false
        )
    }

    @Test("Focus commands activate available modules through the feature model")
    func focusCommandsSwitchModules() {
        let featureModel = makeFeatureModel()

        featureModel.handle(.focusSemanticSearch)
        #expect(featureModel.mode == .semantic)
        #expect(featureModel.isInputFocused)

        featureModel.handle(.focusAddressBar(selectAll: false))
        #expect(featureModel.mode == .address)
        #expect(featureModel.isInputFocused)
    }
}
