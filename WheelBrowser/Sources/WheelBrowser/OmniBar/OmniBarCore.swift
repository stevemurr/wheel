import SwiftUI

/// Consolidated animation state to reduce multiple animation modifiers to one
/// Using a struct with Equatable conformance allows combining multiple values
private struct OmniBarAnimationState: Equatable {
    let shouldExpand: Bool
    let isInputFocused: Bool
    let visiblePanels: UInt8  // Bitmask for panel visibility
}

/// The OmniBar - a unified input bar for URL navigation, AI chat, and semantic search
struct OmniBar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var browserState: BrowserState
    @ObservedObject var agentEngine: AgentEngine
    @StateObject var omniState = OmniBarState()
    @StateObject var suggestionsVM = SuggestionsViewModel()
    @StateObject var semanticSearchVM = SemanticSearchViewModel()
    @StateObject var mentionSuggestionsVM = MentionSuggestionsViewModel()
    @StateObject var readingListVM = ReadingListViewModel()
    @ObservedObject var semanticSearchManager = SemanticSearchManagerV2.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var scrapeManager = ScrapeManager.shared

    let contentExtractor: ContentExtractor

    @State var isInputFocused: Bool = false
    @FocusState var isFindFieldFocused: Bool
    @State var isSending = false
    @State var isHovering = false
    @State var findText: String = ""
    /// Track if current page is saved to reading list
    @State var isCurrentPageSaved: Bool = false

    var shouldExpand: Bool {
        isInputFocused || isHovering
    }

    /// Panel visibility helpers using centralized state method
    var isHistoryPanelVisible: Bool { omniState.isPanelVisible(for: .address) }
    var isChatPanelVisible: Bool { omniState.isPanelVisible(for: .chat) }
    var isSemanticPanelVisible: Bool { omniState.isPanelVisible(for: .semantic) }
    var isAgentPanelVisible: Bool { omniState.isPanelVisible(for: .agent) }
    var isReadingListPanelVisible: Bool { omniState.isPanelVisible(for: .readingList) }
    var isScrapingPanelVisible: Bool { omniState.isPanelVisible(for: .scraping) }

    /// Bitmask combining all panel visibility states for animation consolidation
    private var visiblePanelFlags: UInt8 {
        var flags: UInt8 = 0
        if isHistoryPanelVisible { flags |= 1 }
        if isChatPanelVisible { flags |= 2 }
        if isSemanticPanelVisible { flags |= 4 }
        if isAgentPanelVisible { flags |= 8 }
        if isReadingListPanelVisible { flags |= 16 }
        if downloadManager.showDownloadsPanel { flags |= 32 }
        if isScrapingPanelVisible { flags |= 64 }
        return flags
    }

    var body: some View {
        VStack(spacing: 0) {
            // Panel renderings
            panelViews

            // Mention dropdown panel - appears above OmniBar input when in chat mode with @ trigger
            if omniState.mode == .chat && omniState.showMentionDropdown {
                mentionDropdownPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    .zIndex(1000)
            }

            // Find bar - appears above OmniBar when active
            if tab.isFindBarVisible {
                OmniBarFindBar(tab: tab, findText: $findText, isFocused: _isFindFieldFocused)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // OmniBar itself
            omniBarContent
        }
        .animation(AppAnimation.standard, value: tab.isFindBarVisible)
        .onHover { hovering in
            withAnimation(AppAnimation.medium) {
                isHovering = hovering
            }
        }
        // Consolidated animation for all state changes - uses struct to combine multiple values
        .animation(AppAnimation.panelSpring, value: OmniBarAnimationState(
            shouldExpand: shouldExpand,
            isInputFocused: isInputFocused,
            visiblePanels: visiblePanelFlags
        ))
        .onChange(of: tab.url) { _, newURL in handleURLChange(newURL) }
        .onChange(of: omniState.inputText) { _, newValue in handleInputTextChange(newValue) }
        .onChange(of: isInputFocused) { _, focused in handleFocusChange(focused) }
        .onChange(of: omniState.mode) { _, newMode in handleModeChange(newMode) }
        .onAppear {
            omniState.inputText = tab.url?.absoluteString ?? ""
            suggestionsVM.browserState = browserState
            mentionSuggestionsVM.browserState = browserState
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in handleFocusAddressBar() }
        .onReceive(NotificationCenter.default.publisher(for: .focusAISidebar)) { _ in handleFocusAISidebar() }
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in handleFocusChatInput() }
        .onReceive(NotificationCenter.default.publisher(for: .focusSemanticSearch)) { _ in handleFocusSemanticSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in handleEscapePressed() }
        .onReceive(NotificationCenter.default.publisher(for: .findInPage)) { _ in handleFindInPage() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSavePage)) { _ in toggleSaveCurrentPage() }
        .onReceive(NotificationCenter.default.publisher(for: .focusReadingList)) { _ in handleFocusReadingList() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pageSaveStateChanged"))) { notification in
            handlePageSaveStateChanged(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showScrapePanel)) { _ in
            omniState.setMode(.scraping)
            omniState.setVisiblePanel(.scraping)
        }
        .task {
            await checkIfCurrentPageIsSaved()
        }
    }

    // MARK: - OmniBar Content

    private var omniBarContent: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                // Navigation buttons - only show when expanded in address mode
                if shouldExpand && omniState.mode == .address {
                    navigationButtons
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                // Main input area with suggestions
                inputAreaWithSuggestions
                    .zIndex(100)

                // Panel toggle buttons for modes with content
                panelToggle(for: .chat, hasContent: !agentManager.messages.isEmpty)
                panelToggle(for: .semantic, hasContent: !semanticSearchVM.results.isEmpty)
                panelToggle(for: .agent, hasContent: !agentEngine.steps.isEmpty || agentEngine.isRunning)
                panelToggle(for: .readingList, hasContent: !readingListVM.items.isEmpty)

                // Saved indicator
                if isCurrentPageSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.pink)
                        .transition(.opacity.combined(with: .scale))
                }

                // Zoom indicator (only show if not at 100%)
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

    // MARK: - Navigation Buttons

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

    // MARK: - Panel Toggle Helper

    @ViewBuilder
    func panelToggle(for mode: OmniBarMode, hasContent: Bool) -> some View {
        if omniState.mode == mode && hasContent {
            let panel = mode.correspondingPanel
            PanelToggleButton(isExpanded: omniState.visiblePanel == panel) {
                if omniState.visiblePanel == panel {
                    omniState.dismissVisiblePanel()
                } else {
                    omniState.setVisiblePanel(panel)
                }
            }
        }
    }

    // MARK: - Input Area

    var inputAreaWithSuggestions: some View {
        inputPill
    }
}
