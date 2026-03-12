import SwiftUI

/// The OmniBar - a unified input bar for URL navigation, AI chat, and semantic search
struct OmniBar: View {
    var tab: Tab
    var agentManager: AgentManager
    var browserState: BrowserState
    var noteStore: NoteStore
    var fabricClient: (any WheelFabricMentionClient)?
    var agentEngine: AgentEngine
    @Environment(\.colorScheme) var currentColorScheme
    @State var omniState = OmniBarState()
    @State var suggestionsVM = SuggestionsViewModel()
    @State var semanticSearchVM = SemanticSearchViewModel()
    @State var mentionSuggestionsVM = MentionSuggestionsViewModel()
    @State var readingListVM = ReadingListViewModel()

    let contentExtractor: ContentExtractor

    @State var isInputFocused: Bool = false
    @FocusState var isFindFieldFocused: Bool
    @State var isSending = false
    @State var isHovering = false
    @State var findText: String = ""
    /// Track if current page is saved to reading list
    @State var isCurrentPageSaved: Bool = false
    /// Tracks the chat text editor's calculated height so SwiftUI can constrain it
    @State var chatEditorHeight: CGFloat = OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding

    var shouldExpand: Bool {
        isInputFocused || isHovering
    }

    /// Panel visibility helpers using centralized state method
    var isHistoryPanelVisible: Bool { omniState.isPanelVisible(for: .address) }
    var isSemanticPanelVisible: Bool { omniState.isPanelVisible(for: .semantic) }
    var isAgentPanelVisible: Bool { omniState.isPanelVisible(for: .agent) }
    var isReadingListPanelVisible: Bool { omniState.isPanelVisible(for: .readingList) }
    var shouldTrapTabNavigation: Bool {
        OmniBarState.shouldTrapTabNavigation(
            isInputFocused: isInputFocused,
            visiblePanel: omniState.visiblePanel,
            showMentionDropdown: omniState.showMentionDropdown
        )
    }
    var isFullPageChatActive: Bool {
        tab.url == nil && tab.isChatTab
    }
    var isFullPageChatActiveOrPending: Bool {
        isFullPageChatActive || OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
            tab: tab,
            currentMode: omniState.mode,
            isInputFocused: isInputFocused,
            hasExplicitChatFocusIntent: tab.hasExplicitChatFocusIntent
        )
    }
    var isFullPageChatLocked: Bool {
        isFullPageChatActive && tab.hasConversationStarted
    }
    private var fabricClientIdentity: ObjectIdentifier? {
        fabricClient.map(ObjectIdentifier.init)
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

            // Find bar - animation scoped here so it doesn't affect panelViews
            Group {
                if tab.isFindBarVisible {
                    OmniBarFindBar(tab: tab, findText: $findText, isFocused: _isFindFieldFocused)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppAnimation.standard, value: tab.isFindBarVisible)

            // OmniBar itself — NO .animation() modifier here.
            // The implicit .animation() created an animation context that overlapped
            // with setVisiblePanel()'s withAnimation when focus was gained, because
            // .animation(_:value:) animates ALL state changes in the view when the
            // value changes — not just shouldExpand-derived changes. This double
            // animation context produced the flash. Hover expansion is animated
            // explicitly below; focus-driven expansion is instant (the user is
            // typically already hovering, and the panel animation dominates).
            omniBarContent
        }
        .onHover { hovering in
            withAnimation(AppAnimation.panelSpring) {
                isHovering = hovering
            }
        }
        .background(
            OmniBarTabKeyMonitor(
                isEnabled: shouldTrapTabNavigation,
                onTabPress: { isShiftTab in
                    handleOmniBarTabPress(isShiftTab: isShiftTab)
                }
            )
            .frame(width: 0, height: 0)
        )
        .onChange(of: tab.url) { _, newURL in handleURLChange(newURL) }
        .onChange(of: tab.id) { _, _ in
            // Reset omnibar visual state for the new tab. Defocusing ensures
            // the subsequent setMode → handleModeChange hits the unfocused
            // guard path (dismiss only, no activateMode), preventing stale
            // panels from the previous tab from carrying over.
            isInputFocused = false
            omniState.dismissVisiblePanel()

            agentManager.switchConversation(to: tab.conversationId)
            if tab.isChatTab {
                omniState.setMode(.chat)
                omniState.inputText = ""
            } else if OmniBarTabTransitionPolicy.shouldResetToAddressMode(
                for: tab,
                currentMode: omniState.mode
            ) {
                omniState.setMode(.address)
                omniState.inputText = tab.url?.absoluteString ?? ""
            }
            updateFullPageChatState()
        }
        .onChange(of: omniState.inputText) { _, newValue in handleInputTextChange(newValue) }
        .onChange(of: isInputFocused) { _, focused in handleFocusChange(focused) }
        .onChange(of: omniState.mode) { _, newMode in handleModeChange(newMode) }
        .onAppear {
            omniState.inputText = tab.url?.absoluteString ?? ""
            suggestionsVM.browserState = browserState
            mentionSuggestionsVM.browserState = browserState
            mentionSuggestionsVM.noteStore = noteStore
            mentionSuggestionsVM.fabricClient = fabricClient
            agentManager.switchConversation(to: tab.conversationId)
            updateFullPageChatState()
        }
        .onChange(of: fabricClientIdentity) { _, _ in
            mentionSuggestionsVM.fabricClient = fabricClient
        }
        .modifier(OmniBarNotificationModifier(omniBar: self))
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
                ChatPanelToggle(
                    agentManager: agentManager,
                    omniState: omniState,
                    isSending: isSending,
                    isFullPageChatActiveOrPending: isFullPageChatActiveOrPending
                )
                panelToggle(for: .semantic, hasContent: !semanticSearchVM.results.isEmpty)
                AgentPanelToggle(agentEngine: agentEngine, omniState: omniState)
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

// MARK: - Chat Panel Toggle (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate `agentManager.messages` reads.
/// With `@ObservedObject`, only this sub-view re-evaluates when messages change during streaming,
/// not the entire OmniBar body.
private struct ChatPanelToggle: View {
    var agentManager: AgentManager
    var omniState: OmniBarState
    var isSending: Bool
    var isFullPageChatActiveOrPending: Bool

    var body: some View {
        if omniState.mode == .chat && OmniBarChatPanelVisibilityPolicy.shouldShowFloatingPanel(
            isSending: isSending,
            isLoading: agentManager.isLoading,
            isStreaming: agentManager.isStreamingActive,
            hasMessages: !agentManager.messages.isEmpty,
            isFullPageChatActiveOrPending: isFullPageChatActiveOrPending
        ) {
            let panel = OmniBarMode.chat.correspondingPanel
            PanelToggleButton(isExpanded: omniState.visiblePanel == panel) {
                if omniState.visiblePanel == panel {
                    omniState.dismissVisiblePanel()
                } else {
                    omniState.setVisiblePanel(panel)
                }
            }
        }
    }
}

// MARK: - Agent Panel Toggle (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate `agentEngine.steps` and `agentEngine.isRunning` reads.
private struct AgentPanelToggle: View {
    var agentEngine: AgentEngine
    var omniState: OmniBarState

    var body: some View {
        if omniState.mode == .agent && (!agentEngine.steps.isEmpty || agentEngine.isRunning) {
            let panel = OmniBarMode.agent.correspondingPanel
            PanelToggleButton(isExpanded: omniState.visiblePanel == panel) {
                if omniState.visiblePanel == panel {
                    omniState.dismissVisiblePanel()
                } else {
                    omniState.setVisiblePanel(panel)
                }
            }
        }
    }
}

// MARK: - OmniBar Notification Modifier (extracted to reduce body type-check complexity)

/// Groups all `.onReceive` notification handlers for the OmniBar into a single modifier
/// so the compiler doesn't choke on the main body's expression complexity.
private struct OmniBarNotificationModifier: ViewModifier {
    let omniBar: OmniBar

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in omniBar.handleFocusAddressBar() }
            .onReceive(NotificationCenter.default.publisher(for: .focusAISidebar)) { _ in omniBar.handleFocusAISidebar() }
            .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { notification in
                omniBar.handleFocusChatInput(prefill: notification.object as? String)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSemanticSearch)) { _ in omniBar.handleFocusSemanticSearch() }
            .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in omniBar.handleEscapePressed() }
            .onReceive(NotificationCenter.default.publisher(for: .findInPage)) { _ in omniBar.handleFindInPage() }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSavePage)) { _ in omniBar.toggleSaveCurrentPage() }
            .onReceive(NotificationCenter.default.publisher(for: .focusReadingList)) { _ in omniBar.handleFocusReadingList() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pageSaveStateChanged"))) { notification in
                omniBar.handlePageSaveStateChanged(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyLastResponse)) { _ in
                omniBar.handleCopyLastResponse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .regenerateResponse)) { _ in
                omniBar.handleRegenerateResponse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .editLastMessage)) { _ in
                omniBar.handleEditLastMessage()
            }
    }
}

// MARK: - Panel Subtitle Computed Properties

extension OmniBar {
    var historyPanelSubtitle: String {
        // Single pass to count both tabs and history entries
        var tabCount = 0
        var historyCount = 0
        for suggestion in suggestionsVM.suggestions {
            if suggestion.isOpenTab {
                tabCount += 1
            } else {
                historyCount += 1
            }
        }

        if !omniState.inputText.isEmpty && !suggestionsVM.suggestions.isEmpty {
            var parts: [String] = []
            if tabCount > 0 {
                parts.append("\(tabCount) tab\(tabCount == 1 ? "" : "s")")
            }
            if historyCount > 0 {
                parts.append("\(historyCount) history")
            }
            return parts.joined(separator: ", ")
        }
        return "Tabs & Recent"
    }

    var readingListPanelSubtitle: String {
        if readingListVM.isLoading {
            return "Loading..."
        } else if !readingListVM.items.isEmpty {
            return "\(readingListVM.items.count) saved"
        }
        return ""
    }
}
