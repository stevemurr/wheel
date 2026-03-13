import SwiftUI

@MainActor
@Observable
final class OmniBarFeatureModel: OmniBarCommandHandling {
    @ObservationIgnored let registry: OmniBarModuleRegistry
    @ObservationIgnored let agentManager: AgentManager
    @ObservationIgnored let browserState: BrowserState
    @ObservationIgnored var fabricClient: (any WheelFabricMentionClient)?
    @ObservationIgnored let agentEngine: AgentEngine
    @ObservationIgnored let contentExtractor: ContentExtractor
    @ObservationIgnored private let commandCenter: OmniBarCommandCenter

    @ObservationIgnored var tab: Tab

    var mode: OmniBarModuleID = .address
    var inputText: String = ""
    var visiblePanel: OmniBarPanelVisibility = .none

    var mentions: [Mention] = [.currentPage]
    var showMentionDropdown: Bool = false
    var mentionSearchText: String = ""

    var isInputFocused: Bool = false
    var isHovering: Bool = false
    var isSending = false
    var findText: String = ""
    var isCurrentPageSaved = false
    var chatEditorHeight: CGFloat = OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding
    var findBarFocusRequestToken = 0
    var inputSelectAllRequestToken = 0

    @ObservationIgnored private var suppressedAutomaticMention: Mention?

    init(
        tab: Tab,
        agentManager: AgentManager,
        browserState: BrowserState,
        fabricClient: (any WheelFabricMentionClient)?,
        agentEngine: AgentEngine,
        contentExtractor: ContentExtractor,
        registry: OmniBarModuleRegistry? = nil,
        commandCenter: OmniBarCommandCenter? = nil
    ) {
        self.tab = tab
        self.agentManager = agentManager
        self.browserState = browserState
        self.fabricClient = fabricClient
        self.agentEngine = agentEngine
        self.contentExtractor = contentExtractor
        self.registry = registry ?? .builtIn()
        self.commandCenter = commandCenter ?? .shared

        syncModuleDependencies()
    }

    var currentModule: any OmniBarModule {
        guard let module = registry.module(for: mode) else {
            preconditionFailure("Missing OmniBar module for \(mode.rawValue)")
        }
        return module
    }

    var orderedModuleIDs: [OmniBarModuleID] {
        registry.orderedModuleIDs
    }

    var modeIcon: String {
        currentModule.icon
    }

    var placeholder: String {
        currentModule.placeholder
    }

    var modeColor: Color {
        currentModule.color
    }

    var currentInputKind: OmniBarInputKind {
        currentModule.inputKind
    }

    var shouldExpand: Bool {
        isInputFocused || isHovering
    }

    var isFullPageChatActive: Bool {
        tab.url == nil && tab.isChatTab
    }

    var isFullPageChatActiveOrPending: Bool {
        isFullPageChatActive || OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
            tab: tab,
            currentMode: mode,
            isInputFocused: isInputFocused,
            hasExplicitChatFocusIntent: tab.hasExplicitChatFocusIntent
        )
    }

    var isFullPageChatLocked: Bool {
        isFullPageChatActive && tab.hasConversationStarted
    }

    var historyPanelSubtitle: String {
        let suggestions = addressModule.viewModel.suggestions

        var tabCount = 0
        var historyCount = 0
        for suggestion in suggestions {
            if suggestion.isOpenTab {
                tabCount += 1
            } else {
                historyCount += 1
            }
        }

        if !inputText.isEmpty && !suggestions.isEmpty {
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

    var addressModule: AddressOmniBarModule {
        guard let module = registry.module(for: .address, as: AddressOmniBarModule.self) else {
            preconditionFailure("Missing address OmniBar module")
        }
        return module
    }

    var chatModule: ChatOmniBarModule {
        guard let module = registry.module(for: .chat, as: ChatOmniBarModule.self) else {
            preconditionFailure("Missing chat OmniBar module")
        }
        return module
    }

    var semanticModule: SemanticOmniBarModule {
        guard let module = registry.module(for: .semantic, as: SemanticOmniBarModule.self) else {
            preconditionFailure("Missing semantic OmniBar module")
        }
        return module
    }

    var agentModule: AgentOmniBarModule {
        guard let module = registry.module(for: .agent, as: AgentOmniBarModule.self) else {
            preconditionFailure("Missing agent OmniBar module")
        }
        return module
    }

    var readingListModule: ReadingListOmniBarModule {
        guard let module = registry.module(for: .readingList, as: ReadingListOmniBarModule.self) else {
            preconditionFailure("Missing reading list OmniBar module")
        }
        return module
    }

    func sync(tab: Tab, fabricClient: (any WheelFabricMentionClient)?) {
        self.tab = tab
        self.fabricClient = fabricClient
        syncModuleDependencies()
    }

    func registerCommands() {
        commandCenter.register(self)
    }

    func unregisterCommands() {
        commandCenter.unregister(self)
    }

    func handle(_ command: OmniBarExternalCommand) {
        switch command {
        case .focusAddressBar(let selectAll):
            focusModule(.init(
                moduleID: .address,
                selectAllInput: selectAll
            ))
        case .focusChatInput(let prefill):
            focusModule(.init(
                moduleID: .chat,
                prefill: prefill,
                resetMentions: true,
                explicitChatFocusIntent: true,
                respectsFullPageChatLock: false
            ))
        case .focusAISidebar:
            focusModule(.init(
                moduleID: .chat,
                resetMentions: true,
                explicitChatFocusIntent: true,
                respectsFullPageChatLock: false
            ))
        case .focusSemanticSearch:
            focusModule(.init(moduleID: .semantic))
        case .focusReadingList:
            focusModule(.init(moduleID: .readingList))
        case .escape:
            handleEscapePressed()
        case .findInPage:
            handleFindInPage()
        case .toggleSavePage:
            toggleSaveCurrentPage()
        case .copyLastResponse:
            handleCopyLastResponse()
        case .regenerateResponse:
            handleRegenerateResponse()
        case .editLastMessage:
            handleEditLastMessage()
        }
    }

    func nextMode() {
        setMode(registry.nextID(after: mode))
    }

    func previousMode() {
        setMode(registry.previousID(before: mode))
    }

    func setMode(_ newMode: OmniBarModuleID) {
        guard mode != newMode else { return }
        mode = newMode
        inputText = ""
    }

    func addMention(_ mention: Mention) {
        guard !mentions.contains(mention) else { return }
        if suppressedAutomaticMention == mention {
            suppressedAutomaticMention = nil
        }
        mentions.append(mention)
    }

    func removeMention(_ mention: Mention, userInitiated: Bool = true) {
        mentions.removeAll { $0 == mention }
        if userInitiated && mention.isAutomaticDefaultContext {
            suppressedAutomaticMention = mention
        }
    }

    func resetMentions(includeCurrentPage: Bool = true) {
        let persistent = mentions.filter { $0.isPersistent }
        guard let automaticMention = automaticMention(includeCurrentPage: includeCurrentPage) else {
            mentions = persistent
            return
        }

        if suppressedAutomaticMention == automaticMention {
            mentions = persistent
        } else {
            mentions = [automaticMention] + persistent
        }
    }

    func clearAutomaticMentionSuppression() {
        suppressedAutomaticMention = nil
    }

    func openMentionDropdown() {
        withAnimation(AppAnimation.standard) {
            showMentionDropdown = true
            mentionSearchText = ""
        }
    }

    func dismissMentionDropdown() {
        withAnimation(AppAnimation.standard) {
            showMentionDropdown = false
            mentionSearchText = ""
        }
    }

    func setVisiblePanel(_ panel: OmniBarPanelVisibility) {
        guard visiblePanel != panel else { return }
        withAnimation(AppAnimation.panelSpring) {
            visiblePanel = panel
        }
    }

    func dismissVisiblePanel() {
        guard visiblePanel != .none else { return }
        withAnimation(AppAnimation.panelSpring) {
            visiblePanel = .none
        }
    }

    func isPanelVisible(for moduleID: OmniBarModuleID) -> Bool {
        visiblePanel == moduleID.correspondingPanel && mode == moduleID
    }

    func togglePanel(for moduleID: OmniBarModuleID) {
        let panel = moduleID.correspondingPanel
        if visiblePanel == panel {
            dismissVisiblePanel()
        } else {
            setVisiblePanel(panel)
        }
    }

    func updateFullPageChatState() {
        let targetTabID = tab.id
        DispatchQueue.main.async {
            guard self.tab.id == targetTabID else { return }

            if OmniBarTabTransitionPolicy.shouldLatchEmptyTabIntoChat(
                tab: self.tab,
                currentMode: self.mode,
                isInputFocused: self.isInputFocused,
                hasExplicitChatFocusIntent: self.tab.hasExplicitChatFocusIntent
            ) {
                self.tab.isChatTab = true
                self.tab.hasExplicitChatFocusIntent = false
                return
            }

            if self.tab.isChatTab
                && !self.tab.hasConversationStarted
                && self.tab.url == nil
                && self.mode != .chat {
                self.tab.isChatTab = false
                self.tab.hasExplicitChatFocusIntent = false
            }
        }
    }

    func handleURLChange(_ newURL: URL?) {
        updateFullPageChatState()
        clearAutomaticMentionSuppression()
        if !isInputFocused && mode == .address {
            inputText = newURL?.absoluteString ?? ""
        }
        Task {
            await checkIfCurrentPageIsSaved()
        }
    }

    func handleTabChanged() {
        isInputFocused = false
        dismissVisiblePanel()

        agentManager.switchConversation(to: tab.conversationId)
        if tab.isChatTab {
            setMode(.chat)
            inputText = ""
        } else if OmniBarTabTransitionPolicy.shouldResetToAddressMode(
            for: tab,
            currentMode: mode
        ) {
            setMode(.address)
            inputText = tab.url?.absoluteString ?? ""
        }
        updateFullPageChatState()
    }

    func handleInputTextChange(_ newValue: String) {
        guard isInputFocused else { return }
        currentModule.handleInputChanged(in: self, text: newValue)
    }

    func handleFocusChange(_ focused: Bool) {
        if !focused {
            handleFocusLost()
        } else {
            handleFocusGained()
        }
    }

    func handleInputPillClick() {
        prepareForOmniBarFocus()
        if mode == .chat {
            tab.hasExplicitChatFocusIntent = true
        }
        guard !isInputFocused else { return }
        withAnimation(AppAnimation.panelSpring) {
            isInputFocused = true
        }
    }

    func handleOmniBarTabPress(isShiftTab: Bool) {
        guard Self.shouldTrapTabNavigation(
            isInputFocused: isInputFocused,
            visiblePanel: visiblePanel,
            showMentionDropdown: showMentionDropdown
        ) else { return }

        if !isInputFocused {
            prepareForOmniBarFocus()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isInputFocused = true
            }
        }

        let command: KeyboardCommand = isShiftTab ? .shiftTab : .tab
        _ = handleKeyboardCommand(command, moduleID: mode, text: inputText)
    }

    func handleModeChange(_ newMode: OmniBarModuleID) {
        if newMode != .chat {
            tab.hasExplicitChatFocusIntent = false
        }

        deactivateInactiveModules(except: newMode)
        updateFullPageChatState()

        guard isInputFocused else {
            dismissVisiblePanel()
            return
        }

        currentModule.activate(in: self, reason: .modeSwitch)
    }

    func handleEscapePressed() {
        if agentManager.isStreamingActive {
            agentManager.stopGeneration()
            return
        }

        if DownloadManager.shared.showDownloadsPanel {
            DownloadManager.shared.dismissPanel()
        } else if showMentionDropdown {
            chatModule.dismissMentionSuggestions(in: self)
        } else if tab.isFindBarVisible {
            withAnimation(AppAnimation.standard) {
                tab.hideFindBar()
            }
            findText = ""
        } else if visiblePanel != .none {
            dismissCurrentPanel()
        } else if isInputFocused {
            isInputFocused = false
            if mode == .address {
                inputText = tab.url?.absoluteString ?? ""
            } else {
                inputText = ""
            }
        }
    }

    func handleFindInPage() {
        withAnimation(AppAnimation.standard) {
            tab.showFindBar()
        }
        findBarFocusRequestToken += 1
    }

    func handleCopyLastResponse() {
        guard let lastAssistant = agentManager.messages.last(where: { $0.role == .assistant }) else { return }
        PasteboardHelper.copy(lastAssistant.content)
    }

    func handleRegenerateResponse() {
        guard let lastAssistantID = agentManager.messages.last(where: { $0.role == .assistant })?.id else { return }
        Task {
            await agentManager.regenerateResponse(messageID: lastAssistantID)
        }
    }

    func handleEditLastMessage() {
        focusModule(.init(
            moduleID: .chat,
            respectsFullPageChatLock: false
        ))
    }

    func handlePageSaveStateChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let url = userInfo["url"] as? String,
           let isSaved = userInfo["isSaved"] as? Bool,
           url == tab.url?.absoluteString {
            withAnimation(AppAnimation.medium) {
                isCurrentPageSaved = isSaved
            }
        }
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, moduleID: OmniBarModuleID, text: String) -> Bool {
        if let result = currentModule.handleKeyboardCommand(command, in: self, text: text) {
            return result
        }
        return handleGeneralKeyboardCommand(command, moduleID: moduleID)
    }

    func handleSubmit() {
        currentModule.handleSubmit(in: self)
    }

    func handleSuggestionSelection(_ suggestion: Suggestion) {
        switch suggestion {
        case .openTab(let tab, _, _, _):
            browserState.selectTab(tab.id)
            isInputFocused = false
            dismissVisiblePanel()
            addressModule.viewModel.hide()
            inputText = tab.url?.absoluteString ?? ""
        case .history(let entry, _, _, _):
            guard !self.tab.isChatTab else { return }
            inputText = entry.url
            tab.load(entry.url)
            isInputFocused = false
            dismissVisiblePanel()
            addressModule.viewModel.hide()
        }
    }

    func handleSemanticSelection(_ result: SemanticSearchResult) {
        guard !tab.isChatTab else { return }
        tab.load(result.page.url)
        isInputFocused = false
        dismissVisiblePanel()
        semanticModule.viewModel.clear()
        inputText = ""
    }

    func handleReadingListSelection(_ item: SavedPageRecord) {
        guard !tab.isChatTab else { return }
        tab.load(item.url.absoluteString)
        isInputFocused = false
        dismissVisiblePanel()
        readingListModule.viewModel.clear()
        inputText = ""
    }

    func toggleSaveCurrentPage() {
        guard let url = tab.url else { return }
        let title = tab.title

        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let isSaved = try await database.toggleSaved(url: url.absoluteString, title: title)

                await MainActor.run {
                    withAnimation(AppAnimation.medium) {
                        isCurrentPageSaved = isSaved
                    }
                }

                Log.OmniBar.info("Page \(isSaved ? "saved to" : "removed from") reading list: \(url.absoluteString)")

                if isSaved {
                    Task.detached {
                        await SummaryGenerator.shared.backfillSummaries()
                    }
                }
            } catch {
                Log.OmniBar.error("Failed to toggle save state", error: error)
            }
        }
    }

    func checkIfCurrentPageIsSaved() async {
        guard let url = tab.url else {
            await MainActor.run {
                isCurrentPageSaved = false
            }
            return
        }

        do {
            let database = SearchDatabase.shared
            try await database.initialize()
            let saved = try await database.isSaved(url: url.absoluteString)
            await MainActor.run {
                withAnimation(AppAnimation.medium) {
                    isCurrentPageSaved = saved
                }
            }
        } catch {
            Log.OmniBar.error("Failed to check save state", error: error)
            await MainActor.run {
                isCurrentPageSaved = false
            }
        }
    }

    func removeAtQueryFromInput() {
        let text = inputText
        if let atIndex = text.lastIndex(of: "@") {
            inputText = String(text[..<atIndex])
        }
    }

    static func shouldTrapTabNavigation(
        isInputFocused: Bool,
        visiblePanel: OmniBarPanelVisibility,
        showMentionDropdown: Bool
    ) -> Bool {
        isInputFocused || visiblePanel != .none || showMentionDropdown
    }

    private func syncModuleDependencies() {
        addressModule.viewModel.browserState = browserState
        chatModule.mentionSuggestionsViewModel.browserState = browserState
        chatModule.mentionSuggestionsViewModel.fabricClient = fabricClient
    }

    private func automaticMention(includeCurrentPage: Bool) -> Mention? {
        guard includeCurrentPage else { return nil }
        if let mostRecentOverlay = OverlayWindowManager.shared.windows.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return .overlay(
                id: mostRecentOverlay.id,
                title: mostRecentOverlay.title,
                url: mostRecentOverlay.url.absoluteString
            )
        }
        return .currentPage
    }

    private func prepareForOmniBarFocus() {
        tab.relinquishPageInputFocus()
    }

    private func handleFocusLost() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !self.isInputFocused else { return }
            self.deactivateInactiveModules(except: nil)
            if self.mode == .address || self.mode == .semantic || self.mode == .readingList {
                self.dismissVisiblePanel()
            }
        }
    }

    private func handleFocusGained() {
        updateFullPageChatState()
        currentModule.activate(in: self, reason: .focusGain)
    }

    private func focusModule(_ request: OmniBarFocusRequest) {
        if request.respectsFullPageChatLock && request.moduleID != .chat && isFullPageChatLocked {
            return
        }

        prepareForOmniBarFocus()
        withAnimation(AppAnimation.panelSpring) {
            isInputFocused = true
        }

        if request.explicitChatFocusIntent {
            tab.hasExplicitChatFocusIntent = true
        }
        if request.resetMentions {
            resetMentions(includeCurrentPage: tab.url != nil)
        }

        setMode(request.moduleID)

        if let prefill = request.prefill {
            inputText = prefill
        }
        if request.selectAllInput {
            inputSelectAllRequestToken += 1
        }
    }

    private func dismissCurrentPanel() {
        let panel = visiblePanel
        dismissVisiblePanel()
        isInputFocused = false
        updateFullPageChatState()

        switch panel {
        case .module(let moduleID):
            if moduleID == .address {
                inputText = tab.url?.absoluteString ?? ""
            } else if moduleID != .chat {
                inputText = ""
            }
        case .downloads:
            inputText = ""
        case .none:
            break
        }
    }

    private func deactivateInactiveModules(except activeModuleID: OmniBarModuleID?) {
        for module in registry.modules where module.id != activeModuleID {
            module.deactivate(in: self)
        }
    }

    private func handleGeneralKeyboardCommand(_ command: KeyboardCommand, moduleID: OmniBarModuleID) -> Bool {
        switch command {
        case .submit:
            handleSubmit()
            return true
        case .moveUp:
            guard let selectable = currentModule as? any OmniBarSelectableResultsProviding else {
                return false
            }
            selectable.selectPrevious()
            return true
        case .moveDown:
            guard let selectable = currentModule as? any OmniBarSelectableResultsProviding else {
                return false
            }
            selectable.selectNext()
            return true
        case .tab:
            guard !isFullPageChatLocked else { return true }
            let wasChat = mode == .chat
            nextMode()
            if !wasChat && mode == .chat {
                tab.hasExplicitChatFocusIntent = true
                resetMentions(includeCurrentPage: tab.url != nil)
            }
            return true
        case .shiftTab:
            guard !isFullPageChatLocked else { return true }
            let wasChat = mode == .chat
            previousMode()
            if !wasChat && mode == .chat {
                tab.hasExplicitChatFocusIntent = true
                resetMentions(includeCurrentPage: tab.url != nil)
            }
            return true
        case .escape:
            handleEscapePressed()
            return true
        case .deleteBackward:
            return false
        }
    }
}
