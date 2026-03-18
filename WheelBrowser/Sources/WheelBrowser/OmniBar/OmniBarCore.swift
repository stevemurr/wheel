import AppKit
import SwiftUI

/// The OmniBar - a unified input bar for navigation and browser tools.
struct OmniBar: View {
    var tab: Tab
    var agentManager: AgentManager
    var browserState: BrowserState
    var fabricClient: (any WheelFabricMentionClient)?
    var agentEngine: AgentEngine
    let contentExtractor: ContentExtractor

    @Environment(\.colorScheme) var currentColorScheme
    @State var featureModel: OmniBarFeatureModel
    @FocusState var isFindFieldFocused: Bool

    init(
        tab: Tab,
        agentManager: AgentManager,
        browserState: BrowserState,
        fabricClient: (any WheelFabricMentionClient)?,
        agentEngine: AgentEngine,
        contentExtractor: ContentExtractor
    ) {
        self.tab = tab
        self.agentManager = agentManager
        self.browserState = browserState
        self.fabricClient = fabricClient
        self.agentEngine = agentEngine
        self.contentExtractor = contentExtractor
        _featureModel = State(initialValue: OmniBarFeatureModel(
            tab: tab,
            agentManager: agentManager,
            browserState: browserState,
            fabricClient: fabricClient,
            agentEngine: agentEngine,
            contentExtractor: contentExtractor
        ))
    }

    var omniState: OmniBarFeatureModel { featureModel }

    var suggestionsVM: SuggestionsViewModel { featureModel.addressModule.viewModel }
    var semanticSearchVM: SemanticSearchViewModel { featureModel.semanticModule.viewModel }
    var readingListVM: ReadingListViewModel { featureModel.readingListModule.viewModel }

    var currentPanelProvider: (any OmniBarPanelProviding)? {
        featureModel.currentModule as? any OmniBarPanelProviding
    }

    var currentAccessoryProvider: (any OmniBarAccessoryProviding)? {
        featureModel.currentModule as? any OmniBarAccessoryProviding
    }

    var currentMentionProvider: (any OmniBarMentionProviding)? {
        featureModel.currentModule as? any OmniBarMentionProviding
    }

    var currentMentionSuggestionsViewModel: MentionSuggestionsViewModel? {
        currentMentionProvider?.mentionSuggestionsViewModel
    }

    var shouldTrapTabNavigation: Bool {
        OmniBarFeatureModel.shouldTrapTabNavigation(
            isInputFocused: featureModel.isInputFocused,
            visiblePanel: featureModel.visiblePanel,
            showMentionDropdown: featureModel.showMentionDropdown
        )
    }

    private var fabricClientIdentity: ObjectIdentifier? {
        fabricClient.map(ObjectIdentifier.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            panelViews

            if featureModel.showMentionDropdown,
               let mentionSuggestionsViewModel = currentMentionSuggestionsViewModel {
                mentionDropdownPanel(mentionSuggestionsVM: mentionSuggestionsViewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    .zIndex(1000)
            }

            Group {
                if tab.isFindBarVisible {
                    OmniBarFindBar(
                        tab: tab,
                        findText: $featureModel.findText,
                        isFocused: _isFindFieldFocused
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppAnimation.standard, value: tab.isFindBarVisible)

            omniBarContent
        }
        .onHover { hovering in
            withAnimation(AppAnimation.panelSpring) {
                featureModel.isHovering = hovering
            }
        }
        .background(
            OmniBarTabKeyMonitor(
                isEnabled: shouldTrapTabNavigation,
                onTabPress: { isShiftTab in
                    featureModel.handleOmniBarTabPress(isShiftTab: isShiftTab)
                }
            )
            .frame(width: 0, height: 0)
        )
        .onChange(of: tab.url) { _, newURL in
            featureModel.sync(tab: tab, fabricClient: fabricClient)
            featureModel.handleURLChange(newURL)
        }
        .onChange(of: tab.id) { _, _ in
            featureModel.sync(tab: tab, fabricClient: fabricClient)
            featureModel.handleTabChanged()
        }
        .onChange(of: featureModel.inputText) { _, newValue in
            featureModel.handleInputTextChange(newValue)
        }
        .onChange(of: featureModel.isInputFocused) { _, focused in
            featureModel.handleFocusChange(focused)
        }
        .onChange(of: featureModel.mode) { _, newMode in
            featureModel.handleModeChange(newMode)
        }
        .onChange(of: fabricClientIdentity) { _, _ in
            featureModel.sync(tab: tab, fabricClient: fabricClient)
        }
        .onChange(of: featureModel.findBarFocusRequestToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFindFieldFocused = true
            }
        }
        .onChange(of: featureModel.inputSelectAllRequestToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.keyWindow,
                   let fieldEditor = window.firstResponder as? NSTextView {
                    fieldEditor.selectAll(nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pageSaveStateChanged"))) { notification in
            featureModel.handlePageSaveStateChanged(notification)
        }
        .onAppear {
            featureModel.sync(tab: tab, fabricClient: fabricClient)
            featureModel.inputText = tab.url?.absoluteString ?? ""
            agentManager.switchConversation(to: tab.conversationId)
            featureModel.updateFullPageChatState()
            featureModel.registerCommands()
        }
        .onDisappear {
            featureModel.unregisterCommands()
        }
        .task {
            await featureModel.checkIfCurrentPageIsSaved()
        }
    }

    private var omniBarContent: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                if featureModel.shouldExpand && featureModel.mode == .address {
                    navigationButtons
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                inputPill
                    .zIndex(100)

                currentModulePanelToggle

                if featureModel.isCurrentPageSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.pink)
                        .transition(.opacity.combined(with: .scale))
                }

                if tab.zoomLevel != 1.0 {
                    Text("\(Int(tab.zoomLevel * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)

            Spacer()
        }
    }

    var navigationButtons: some View {
        HStack(spacing: 8) {
            NavigationButton(
                icon: "chevron.left",
                isEnabled: tab.canGoBack,
                action: { tab.goBack() }
            )

            NavigationButton(
                icon: "chevron.right",
                isEnabled: tab.canGoForward,
                action: { tab.goForward() }
            )

            NavigationButton(
                icon: tab.isLoading ? "xmark" : "arrow.clockwise",
                isEnabled: true,
                action: {
                    if tab.isLoading {
                        tab.stopLoading()
                    } else {
                        tab.reload()
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var currentModulePanelToggle: some View {
        if let panelProvider = currentPanelProvider,
           panelProvider.showsPanelToggle(in: featureModel) {
            let panel = featureModel.mode.correspondingPanel
            PanelToggleButton(isExpanded: featureModel.visiblePanel == panel) {
                featureModel.togglePanel(for: featureModel.mode)
            }
        }
    }
}
