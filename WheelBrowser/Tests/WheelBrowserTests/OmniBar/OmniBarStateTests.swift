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
            agentEngine: agentEngine
        )
    }

    @Test("Tab trapping stays active while any OmniBar surface is active")
    func tabTrappingActivatesForFocusedInputOrPanels() {
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: true,
                visiblePanel: .none
            )
        )
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: false,
                visiblePanel: .semantic
            )
        )
    }

    @Test("Tab trapping stays off when the OmniBar is fully inactive")
    func tabTrappingStaysOffWhenOmniBarIsInactive() {
        #expect(
            OmniBarFeatureModel.shouldTrapTabNavigation(
                isInputFocused: false,
                visiblePanel: .none
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

    @Test("Hidden OmniBar modes fall back to address mode")
    func hiddenModesFallBackToAddress() {
        let featureModel = makeFeatureModel()

        featureModel.setMode(.agent)
        #expect(featureModel.mode == .address)
    }
}
