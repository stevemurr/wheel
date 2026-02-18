import SwiftUI

/// The OmniBar - a unified input bar for URL navigation, AI chat, and semantic search
struct OmniBar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var browserState: BrowserState
    @ObservedObject var agentEngine: AgentEngine
    @StateObject private var omniState = OmniBarState()
    @StateObject private var suggestionsVM = SuggestionsViewModel()
    @StateObject private var semanticSearchVM = SemanticSearchViewModel()
    @StateObject private var mentionSuggestionsVM = MentionSuggestionsViewModel()
    @ObservedObject private var semanticSearchManager = SemanticSearchManagerV2.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    let contentExtractor: ContentExtractor

    @State private var isInputFocused: Bool = false
    @FocusState private var isFindFieldFocused: Bool
    @State private var isSending = false
    @State private var isHovering = false
    @State private var findText: String = ""
    /// Track if the view has appeared to prevent initial animation flash
    @State private var hasAppeared: Bool = false

    private var shouldExpand: Bool {
        isInputFocused || isHovering
    }

    /// Computed property to determine if history panel should be visible
    private var isHistoryPanelVisible: Bool {
        omniState.showHistoryPanel && omniState.mode == .address
    }

    /// Computed property to determine if chat panel should be visible
    private var isChatPanelVisible: Bool {
        omniState.showChatPanel && omniState.mode == .chat
    }

    /// Computed property to determine if semantic panel should be visible
    private var isSemanticPanelVisible: Bool {
        omniState.showSemanticPanel && omniState.mode == .semantic
    }

    /// Computed property to determine if agent panel should be visible
    private var isAgentPanelVisible: Bool {
        omniState.showAgentPanel && omniState.mode == .agent
    }

    private var historyPanelSubtitle: String {
        let tabCount = suggestionsVM.suggestions.filter { $0.isOpenTab }.count
        let historyCount = suggestionsVM.suggestions.filter { !$0.isOpenTab }.count

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

    private var semanticPanelSubtitle: String {
        if semanticSearchVM.isSearching {
            return "Searching..."
        } else if !semanticSearchVM.results.isEmpty {
            return "\(semanticSearchVM.results.count) results"
        }
        return "\(semanticSearchManager.indexedCount) pages indexed"
    }

    private var downloadsPanelSubtitle: String {
        let activeCount = downloadManager.downloads.filter { $0.status == .downloading }.count
        if activeCount > 0 {
            return "\(activeCount) downloading"
        } else if !downloadManager.downloads.isEmpty {
            return "\(downloadManager.downloads.count) items"
        }
        return ""
    }

    private var agentPanelSubtitle: String {
        if agentEngine.isRunning {
            return agentEngine.progress
        } else if !agentEngine.steps.isEmpty {
            if let lastStep = agentEngine.steps.last, lastStep.type == .done {
                return "Completed"
            } else if agentEngine.error != nil {
                return "Failed"
            }
            return "\(agentEngine.steps.count) steps"
        }
        return "Ready"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Suggestions panel - appears above OmniBar when in address mode (shows tabs + history)
            OmniPanel(
                title: "Go to",
                icon: "magnifyingglass",
                iconColor: .accentColor,
                borderColor: .blue,
                subtitle: historyPanelSubtitle,
                onDismiss: {
                    omniState.dismissHistoryPanel()
                }
            ) {
                HistoryPanelContent(
                    viewModel: suggestionsVM,
                    searchText: omniState.inputText,
                    onSelect: { suggestion in
                        handleSuggestionSelection(suggestion)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(isHistoryPanelVisible ? 1 : 0)
            .scaleEffect(isHistoryPanelVisible ? 1 : 0.95)
            .offset(y: isHistoryPanelVisible ? 0 : 10)
            .allowsHitTesting(isHistoryPanelVisible)
            .frame(maxHeight: isHistoryPanelVisible ? nil : 0)
            .clipped()
            .animation(hasAppeared ? .spring(response: 0.3, dampingFraction: 0.85) : nil, value: isHistoryPanelVisible)
            .zIndex(999)

            // Chat panel - appears above OmniBar when in chat mode
            OmniPanel(
                title: "Claude",
                icon: "sparkles",
                iconColor: .purple,
                borderColor: .purple,
                subtitle: agentManager.isLoading ? "Thinking..." : nil,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Clear Chat") {
                                agentManager.clearMessages()
                            }
                            Divider()
                            Button("Reset Agent", role: .destructive) {
                                Task { await agentManager.resetAgent() }
                            }
                        }
                    )
                },
                onDismiss: {
                    omniState.dismissChatPanel()
                }
            ) {
                ChatPanelContent(agentManager: agentManager)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(isChatPanelVisible ? 1 : 0)
            .scaleEffect(isChatPanelVisible ? 1 : 0.95)
            .offset(y: isChatPanelVisible ? 0 : 10)
            .allowsHitTesting(isChatPanelVisible)
            .frame(maxHeight: isChatPanelVisible ? nil : 0)
            .clipped()
            .animation(hasAppeared ? .spring(response: 0.3, dampingFraction: 0.85) : nil, value: isChatPanelVisible)
            .zIndex(999)

            // Semantic search panel - appears above OmniBar when in semantic mode
            OmniPanel(
                title: "Semantic Search",
                icon: "brain.head.profile",
                iconColor: .orange,
                borderColor: .orange,
                subtitle: semanticPanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Clear Index") {
                                Task { await semanticSearchManager.clearIndex() }
                            }
                        }
                    )
                },
                onDismiss: {
                    omniState.dismissSemanticPanel()
                }
            ) {
                SemanticSearchPanelContent(
                    viewModel: semanticSearchVM,
                    searchManager: semanticSearchManager,
                    searchText: omniState.inputText,
                    onSelect: { result in
                        handleSemanticSelection(result)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(isSemanticPanelVisible ? 1 : 0)
            .scaleEffect(isSemanticPanelVisible ? 1 : 0.95)
            .offset(y: isSemanticPanelVisible ? 0 : 10)
            .allowsHitTesting(isSemanticPanelVisible)
            .frame(maxHeight: isSemanticPanelVisible ? nil : 0)
            .clipped()
            .animation(hasAppeared ? .spring(response: 0.3, dampingFraction: 0.85) : nil, value: isSemanticPanelVisible)
            .zIndex(999)

            // Agent panel - appears above OmniBar when in agent mode
            OmniPanel(
                title: "Agent",
                icon: "wand.and.stars",
                iconColor: .green,
                borderColor: .green,
                subtitle: agentPanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Cancel Task") {
                                agentEngine.cancel()
                            }
                            .disabled(!agentEngine.isRunning)
                            Divider()
                            Button("Clear History") {
                                agentEngine.steps = []
                            }
                            .disabled(agentEngine.steps.isEmpty)
                        }
                    )
                },
                onDismiss: {
                    omniState.dismissAgentPanel()
                }
            ) {
                AgentPanelContent(agentEngine: agentEngine)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(isAgentPanelVisible ? 1 : 0)
            .scaleEffect(isAgentPanelVisible ? 1 : 0.95)
            .offset(y: isAgentPanelVisible ? 0 : 10)
            .allowsHitTesting(isAgentPanelVisible)
            .frame(maxHeight: isAgentPanelVisible ? nil : 0)
            .clipped()
            .animation(hasAppeared ? .spring(response: 0.3, dampingFraction: 0.85) : nil, value: isAgentPanelVisible)
            .zIndex(999)

            // Downloads panel - appears above OmniBar when downloads are active
            OmniPanel(
                title: "Downloads",
                icon: "arrow.down.circle.fill",
                iconColor: .blue,
                borderColor: .blue,
                subtitle: downloadsPanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Clear Completed") {
                                downloadManager.clearCompleted()
                            }
                            Button("Show in Finder") {
                                if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    )
                },
                onDismiss: {
                    downloadManager.dismissPanel()
                }
            ) {
                DownloadsPanelContent(manager: downloadManager)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(downloadManager.showDownloadsPanel ? 1 : 0)
            .scaleEffect(downloadManager.showDownloadsPanel ? 1 : 0.95)
            .offset(y: downloadManager.showDownloadsPanel ? 0 : 10)
            .allowsHitTesting(downloadManager.showDownloadsPanel)
            .frame(maxHeight: downloadManager.showDownloadsPanel ? nil : 0)
            .clipped()
            .animation(hasAppeared ? .spring(response: 0.3, dampingFraction: 0.85) : nil, value: downloadManager.showDownloadsPanel)
            .zIndex(999)

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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldExpand)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isInputFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: omniState.showChatPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: omniState.showSemanticPanel)
        .onChange(of: tab.url) { _, newURL in
            if !isInputFocused && omniState.mode == .address {
                omniState.inputText = newURL?.absoluteString ?? ""
            }
        }
        .onChange(of: omniState.inputText) { _, newValue in
            if isInputFocused {
                switch omniState.mode {
                case .address:
                    if newValue.isEmpty {
                        suggestionsVM.loadRecentHistory()
                    } else {
                        suggestionsVM.updateSuggestions(for: newValue)
                    }
                case .semantic:
                    semanticSearchVM.search(query: newValue)
                case .chat:
                    break
                case .agent:
                    break
                }
            }
        }
        .onChange(of: isInputFocused) { _, focused in
            omniState.isFocused = focused
            if !focused {
                // Delay hiding to allow click on suggestion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    suggestionsVM.hide()
                    semanticSearchVM.clear()
                    if omniState.mode == .address {
                        omniState.dismissHistoryPanel()
                    } else if omniState.mode == .semantic {
                        omniState.dismissSemanticPanel()
                    }
                }
            } else {
                switch omniState.mode {
                case .address:
                    omniState.openHistoryPanel()
                    if omniState.inputText.isEmpty {
                        suggestionsVM.loadRecentHistory()
                    } else {
                        suggestionsVM.updateSuggestions(for: omniState.inputText)
                    }
                case .semantic:
                    omniState.openSemanticPanel()
                    if !omniState.inputText.isEmpty {
                        semanticSearchVM.search(query: omniState.inputText)
                    }
                case .chat:
                    break
                case .agent:
                    omniState.openAgentPanel()
                }
            }
        }
        .onChange(of: omniState.mode) { _, newMode in
            // Handle panel visibility based on mode
            switch newMode {
            case .chat:
                suggestionsVM.hide()
                semanticSearchVM.clear()
                omniState.dismissHistoryPanel()
                omniState.dismissSemanticPanel()
                omniState.dismissAgentPanel()
                if !agentManager.messages.isEmpty {
                    omniState.openChatPanel()
                }
            case .address:
                semanticSearchVM.clear()
                omniState.dismissChatPanel()
                omniState.dismissSemanticPanel()
                omniState.dismissAgentPanel()
                if isInputFocused {
                    omniState.openHistoryPanel()
                }
            case .semantic:
                suggestionsVM.hide()
                omniState.dismissChatPanel()
                omniState.dismissHistoryPanel()
                omniState.dismissAgentPanel()
                omniState.openSemanticPanel()
                if !omniState.inputText.isEmpty {
                    semanticSearchVM.search(query: omniState.inputText)
                }
            case .agent:
                suggestionsVM.hide()
                semanticSearchVM.clear()
                omniState.dismissChatPanel()
                omniState.dismissHistoryPanel()
                omniState.dismissSemanticPanel()
                omniState.openAgentPanel()
            }
        }
        .onAppear {
            omniState.inputText = tab.url?.absoluteString ?? ""
            suggestionsVM.browserState = browserState
            mentionSuggestionsVM.browserState = browserState
            Task {
                if !agentManager.isReady && !agentManager.isLoading {
                    await agentManager.initialize()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in
            omniState.setMode(.address)
            isInputFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.keyWindow,
                   let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
                    fieldEditor.selectAll(nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAISidebar)) { _ in
            omniState.setMode(.chat)
            isInputFocused = true
            if !agentManager.messages.isEmpty {
                omniState.openChatPanel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in
            omniState.setMode(.chat)
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSemanticSearch)) { _ in
            omniState.setMode(.semantic)
            isInputFocused = true
            omniState.openSemanticPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in
            if omniState.showMentionDropdown {
                omniState.dismissMentionDropdown()
                mentionSuggestionsVM.clear()
            } else if tab.isFindBarVisible {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tab.hideFindBar()
                }
                findText = ""
            } else if omniState.showHistoryPanel {
                omniState.dismissHistoryPanel()
                isInputFocused = false
                omniState.inputText = tab.url?.absoluteString ?? ""
            } else if omniState.showChatPanel {
                omniState.dismissChatPanel()
                isInputFocused = false
            } else if omniState.showSemanticPanel {
                omniState.dismissSemanticPanel()
                isInputFocused = false
                omniState.inputText = ""
            } else if omniState.showAgentPanel {
                omniState.dismissAgentPanel()
                isInputFocused = false
                omniState.inputText = ""
            } else if isInputFocused {
                isInputFocused = false
                if omniState.mode == .address {
                    omniState.inputText = tab.url?.absoluteString ?? ""
                } else if omniState.mode == .semantic || omniState.mode == .agent {
                    omniState.inputText = ""
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInPage)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                tab.showFindBar()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFindFieldFocused = true
            }
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
            .padding(.vertical, 12)

            Spacer()
        }
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.95),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
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

    private var inputAreaWithSuggestions: some View {
        inputPill
    }

    // MARK: - Input Pill

    private var inputPill: some View {
        HStack(spacing: 8) {
            // Mode indicator icon
            modeIndicator

            // Mention chips (only in chat mode)
            if omniState.mode == .chat {
                mentionChips
            }

            // Input field
            OmniBarTextField(
                text: $omniState.inputText,
                isFocused: $isInputFocused,
                mode: omniState.mode,
                suggestionsVM: suggestionsVM,
                semanticSearchVM: semanticSearchVM,
                mentionSuggestionsVM: mentionSuggestionsVM,
                omniState: omniState,
                placeholder: omniState.mode == .chat && !omniState.mentions.isEmpty ? "Ask about these pages..." : omniState.placeholder,
                onSubmit: handleSubmit,
                onTabPress: {
                    omniState.nextMode()
                },
                onShiftTabPress: {
                    omniState.previousMode()
                },
                onAtTrigger: { query in
                    handleAtTrigger(query: query)
                },
                onMentionSelect: {
                    handleMentionSelection()
                }
            )

            // Action button (clear in address mode, send in chat mode)
            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: shouldExpand ? 400 : 280, maxWidth: shouldExpand ? 540 : 360)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(
                    color: isInputFocused ? omniState.modeColor.opacity(0.3) : Color.black.opacity(0.15),
                    radius: isInputFocused ? 8 : 4,
                    x: 0,
                    y: 2
                )
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    isInputFocused ? omniState.modeColor.opacity(0.6) : Color.white.opacity(0.1),
                    lineWidth: isInputFocused ? 2 : 1
                )
        }
    }

    // MARK: - Mention Chips

    private var mentionChips: some View {
        HStack(spacing: 4) {
            ForEach(omniState.mentions) { mention in
                MentionChip(mention: mention) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        omniState.removeMention(mention)
                    }
                }
            }
        }
    }

    // MARK: - Mention Dropdown Panel

    private var mentionDropdownPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mentionSuggestionsVM.suggestions.isEmpty {
                if mentionSuggestionsVM.isSearching {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Searching...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                } else {
                    Text("No matches found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(mentionSuggestionsVM.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            MentionSuggestionRow(
                                suggestion: suggestion,
                                isSelected: index == mentionSuggestionsVM.selectedIndex,
                                onSelect: {
                                    selectMentionSuggestion(suggestion)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Mention Handling

    private func handleAtTrigger(query: String) {
        if !omniState.showMentionDropdown {
            omniState.openMentionDropdown()
        }
        omniState.mentionSearchText = query
        mentionSuggestionsVM.updateSuggestions(
            for: query,
            excluding: omniState.mentions,
            currentTabId: tab.id
        )
    }

    private func handleMentionSelection() {
        guard let suggestion = mentionSuggestionsVM.selectedSuggestion else { return }
        selectMentionSuggestion(suggestion)
    }

    private func selectMentionSuggestion(_ suggestion: MentionSuggestion) {
        withAnimation(.easeInOut(duration: 0.15)) {
            omniState.addMention(suggestion.mention)
            omniState.dismissMentionDropdown()
        }
        mentionSuggestionsVM.clear()

        // Remove the @query from input text
        removeAtQueryFromInput()
    }

    private func removeAtQueryFromInput() {
        // Find and remove @... pattern from input
        let text = omniState.inputText
        if let atIndex = text.lastIndex(of: "@") {
            omniState.inputText = String(text[..<atIndex])
        }
    }

    // MARK: - Mode Indicator

    private var modeIndicator: some View {
        Button(action: { omniState.nextMode() }) {
            Image(systemName: omniState.modeIcon)
                .foregroundColor(isInputFocused ? omniState.modeColor : .secondary)
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help("Press Tab to switch modes (Address / Chat / Semantic)")
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch omniState.mode {
        case .address:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    suggestionsVM.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .chat:
            Button(action: handleSubmit) {
                ZStack {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(omniState.inputText.isEmpty ? .secondary : .white)
                    }
                }
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(omniState.inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.purple)
                )
            }
            .buttonStyle(.plain)
            .disabled(omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

        case .semantic:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    semanticSearchVM.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .agent:
            Button(action: handleSubmit) {
                ZStack {
                    if agentEngine.isRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(omniState.inputText.isEmpty ? .secondary : .white)
                    }
                }
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(omniState.inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.green)
                )
            }
            .buttonStyle(.plain)
            .disabled(omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentEngine.isRunning)
        }
    }

    // MARK: - Actions

    private func handleSubmit() {
        switch omniState.mode {
        case .address:
            submitAddress()
        case .chat:
            submitChat()
        case .semantic:
            submitSemantic()
        case .agent:
            submitAgent()
        }
    }

    private func submitAddress() {
        if let selected = suggestionsVM.selectedSuggestion {
            handleSuggestionSelection(selected)
            return
        }
        tab.load(omniState.inputText)
        isInputFocused = false
        suggestionsVM.hide()
        omniState.dismissHistoryPanel()
    }

    private func handleSuggestionSelection(_ suggestion: Suggestion) {
        switch suggestion {
        case .openTab(let tab, _):
            browserState.selectTab(tab.id)
            isInputFocused = false
            omniState.dismissHistoryPanel()
            suggestionsVM.hide()
            omniState.inputText = tab.url?.absoluteString ?? ""

        case .history(let entry, _):
            omniState.inputText = entry.url
            self.tab.load(entry.url)
            isInputFocused = false
            omniState.dismissHistoryPanel()
            suggestionsVM.hide()
        }
    }

    private func submitChat() {
        let content = omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        // Capture mentions before clearing
        let currentMentions = omniState.mentions

        omniState.inputText = ""
        isSending = true

        omniState.openChatPanel()

        Task {
            // Extract content from all mentioned sources
            var pageContexts: [PageContext] = []

            for mention in currentMentions {
                switch mention {
                case .currentPage:
                    if let context = await contentExtractor.extractContent(from: tab) {
                        pageContexts.append(context)
                    }

                case .tab(let tabId, _, _):
                    // Find the tab and extract its content
                    if let mentionedTab = browserState.tabs.first(where: { $0.id == tabId }) {
                        if let context = await contentExtractor.extractContent(from: mentionedTab) {
                            pageContexts.append(context)
                        }
                    }

                case .semanticResult(_, _, let url):
                    // For semantic results, we include the URL as context
                    // The actual content would need to be fetched, but for now we provide URL info
                    let semanticContext = PageContext(
                        url: url,
                        title: mention.displayTitle,
                        textContent: "[Content from browsing history - URL: \(url)]"
                    )
                    pageContexts.append(semanticContext)
                }
            }

            await agentManager.sendMessage(content, pageContexts: pageContexts)
            isSending = false

            // Reset mentions to default after sending
            omniState.resetMentions()
        }
    }

    private func submitSemantic() {
        if let selected = semanticSearchVM.selectedResult {
            handleSemanticSelection(selected)
        }
    }

    private func handleSemanticSelection(_ result: SemanticSearchResult) {
        tab.load(result.page.url)
        isInputFocused = false
        omniState.dismissSemanticPanel()
        semanticSearchVM.clear()
        omniState.inputText = ""
    }

    private func submitAgent() {
        let task = omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        omniState.inputText = ""
        omniState.openAgentPanel()

        Task {
            _ = await agentEngine.run(task: task)
        }
    }
}

// MARK: - Custom TextField for OmniBar

struct OmniBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let mode: OmniBarMode
    @ObservedObject var suggestionsVM: SuggestionsViewModel
    @ObservedObject var semanticSearchVM: SemanticSearchViewModel
    @ObservedObject var mentionSuggestionsVM: MentionSuggestionsViewModel
    @ObservedObject var omniState: OmniBarState
    let placeholder: String
    var onSubmit: () -> Void
    var onTabPress: () -> Void
    var onShiftTabPress: () -> Void
    var onAtTrigger: (String) -> Void
    var onMentionSelect: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textFieldAction(_:))
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder

        if isFocused && nsView.window != nil && nsView.window?.firstResponder != nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OmniBarTextField
        private var isEditing = false

        init(_ parent: OmniBarTextField) {
            self.parent = parent
        }

        @objc func textFieldAction(_ sender: NSTextField) {
            parent.onSubmit()
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard isEditing else { return }
            isEditing = false

            if let textField = obj.object as? NSTextField {
                DispatchQueue.main.async {
                    let isStillFocused = textField.window?.firstResponder == textField.currentEditor()
                    if !isStillFocused {
                        self.parent.isFocused = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.isFocused = false
                }
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                let newText = textField.stringValue
                parent.text = newText

                // Check for @ trigger in chat mode
                if parent.mode == .chat {
                    checkForAtTrigger(in: newText)
                }
            }
        }

        private func checkForAtTrigger(in text: String) {
            // Find the last @ and extract the query after it
            if let atIndex = text.lastIndex(of: "@") {
                let queryStartIndex = text.index(after: atIndex)
                let query = String(text[queryStartIndex...])

                // Check if @ is at start or preceded by whitespace
                let isValidTrigger: Bool
                if atIndex == text.startIndex {
                    isValidTrigger = true
                } else {
                    let beforeAt = text.index(before: atIndex)
                    let charBeforeAt = text[beforeAt]
                    isValidTrigger = charBeforeAt.isWhitespace
                }

                // Only trigger if query doesn't contain spaces (single word/partial)
                if isValidTrigger && !query.contains(" ") {
                    DispatchQueue.main.async {
                        self.parent.onAtTrigger(query)
                    }
                    return
                }
            }

            // No valid @ trigger - dismiss dropdown if open
            DispatchQueue.main.async { [self] in
                Task { @MainActor in
                    if self.parent.omniState.showMentionDropdown {
                        self.parent.omniState.dismissMentionDropdown()
                        self.parent.mentionSuggestionsVM.clear()
                    }
                }
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // For chat mode, we need to handle mention navigation
            // We dispatch to main async for MainActor-isolated properties
            if parent.mode == .chat {
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    DispatchQueue.main.async {
                        Task { @MainActor in
                            if self.parent.omniState.showMentionDropdown {
                                self.parent.mentionSuggestionsVM.selectPrevious()
                            }
                        }
                    }
                    return true
                } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    DispatchQueue.main.async {
                        Task { @MainActor in
                            if self.parent.omniState.showMentionDropdown {
                                self.parent.mentionSuggestionsVM.selectNext()
                            }
                        }
                    }
                    return true
                } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    DispatchQueue.main.async {
                        Task { @MainActor in
                            if self.parent.omniState.showMentionDropdown && !self.parent.mentionSuggestionsVM.suggestions.isEmpty {
                                self.parent.onMentionSelect()
                            } else {
                                self.parent.onSubmit()
                            }
                        }
                    }
                    return true
                } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    DispatchQueue.main.async {
                        Task { @MainActor in
                            if self.parent.omniState.showMentionDropdown {
                                self.parent.omniState.dismissMentionDropdown()
                                self.parent.mentionSuggestionsVM.clear()
                            } else {
                                NotificationCenter.default.post(name: .escapePressed, object: nil)
                            }
                        }
                    }
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                switch parent.mode {
                case .address:
                    parent.suggestionsVM.selectPrevious()
                    return true
                case .semantic:
                    parent.semanticSearchVM.selectPrevious()
                    return true
                case .chat, .agent:
                    return false
                }
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                switch parent.mode {
                case .address:
                    parent.suggestionsVM.selectNext()
                    return true
                case .semantic:
                    parent.semanticSearchVM.selectNext()
                    return true
                case .chat, .agent:
                    return false
                }
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTabPress()
                return true
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onShiftTabPress()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                NotificationCenter.default.post(name: .escapePressed, object: nil)
                return true
            }
            return false
        }
    }
}

// MARK: - Navigation Button

private struct NavigationButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - OmniBar Find Bar

struct OmniBarFindBar: View {
    @ObservedObject var tab: Tab
    @Binding var findText: String
    @FocusState var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11, weight: .medium))

                    TextField("Find in page", text: $findText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isFocused)
                        .onChange(of: findText) { _, newValue in
                            tab.findInPage(newValue)
                        }
                        .onSubmit {
                            tab.findNext()
                        }

                    if !findText.isEmpty {
                        Button(action: { findText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 220)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                }

                HStack(spacing: 4) {
                    Button(action: { tab.findPrevious() }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(findText.isEmpty ? .secondary.opacity(0.5) : .primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.clear)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findText.isEmpty)

                    Button(action: { tab.findNext() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(findText.isEmpty ? .secondary.opacity(0.5) : .primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.clear)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findText.isEmpty)
                }

                Button(action: {
                    tab.hideFindBar()
                    findText = ""
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle()
                                .fill(Color.clear)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()
        }
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.95)
        }
    }
}
