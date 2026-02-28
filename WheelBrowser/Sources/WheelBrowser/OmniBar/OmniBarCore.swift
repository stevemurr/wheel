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
    /// Track if the view has appeared to prevent initial animation flash
    @State var hasAppeared: Bool = false
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
    // NOTE: Dual source of truth — intentionally checks both omniState and scrapeManager
    // because scraping can be triggered externally (e.g., keyboard shortcut) bypassing omniState.
    // A future refactor should unify these into a single state source.
    var isScrapingPanelVisible: Bool { omniState.isPanelVisible(for: .scraping) || scrapeManager.showScrapePanel }

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
        .animation(.easeInOut(duration: 0.15), value: tab.isFindBarVisible)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        // Consolidated animation for all state changes - uses struct to combine multiple values
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: OmniBarAnimationState(
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
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

                // Chat panel toggle (only in chat mode with messages)
                if omniState.mode == .chat && !agentManager.messages.isEmpty {
                    Button(action: {
                        if omniState.showChatPanel {
                            omniState.dismissChatPanel()
                        } else {
                            omniState.openChatPanel()
                        }
                    }) {
                        Image(systemName: omniState.showChatPanel ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }

                // Semantic panel toggle (only in semantic mode with results)
                if omniState.mode == .semantic && !semanticSearchVM.results.isEmpty {
                    Button(action: {
                        if omniState.showSemanticPanel {
                            omniState.dismissSemanticPanel()
                        } else {
                            omniState.openSemanticPanel()
                        }
                    }) {
                        Image(systemName: omniState.showSemanticPanel ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }

                // Agent panel toggle (only in agent mode with steps or running)
                if omniState.mode == .agent && (!agentEngine.steps.isEmpty || agentEngine.isRunning) {
                    Button(action: {
                        if omniState.showAgentPanel {
                            omniState.dismissAgentPanel()
                        } else {
                            omniState.openAgentPanel()
                        }
                    }) {
                        Image(systemName: omniState.showAgentPanel ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }

                // Reading list panel toggle (only in reading list mode with items)
                if omniState.mode == .readingList && !readingListVM.items.isEmpty {
                    Button(action: {
                        if omniState.showReadingListPanel {
                            omniState.dismissReadingListPanel()
                        } else {
                            omniState.openReadingListPanel()
                        }
                    }) {
                        Image(systemName: omniState.showReadingListPanel ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }

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

    // MARK: - Input Area

    var inputAreaWithSuggestions: some View {
        inputPill
    }
}
