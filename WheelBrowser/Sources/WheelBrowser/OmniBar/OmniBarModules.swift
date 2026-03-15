import SwiftUI

struct OmniBarPanelDescriptor {
    let moduleID: OmniBarModuleID
    let title: String
    let icon: String
    let iconColor: Color
    let borderColor: Color
    let subtitle: String?
    let menuContent: AnyView?
    let content: AnyView
}

@MainActor
protocol OmniBarModule: AnyObject {
    var id: OmniBarModuleID { get }
    var title: String { get }
    var icon: String { get }
    var placeholder: String { get }
    var color: Color { get }
    var inputKind: OmniBarInputKind { get }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason)
    func deactivate(in featureModel: OmniBarFeatureModel)
    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String)
    func handleSubmit(in featureModel: OmniBarFeatureModel)
    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool?
    func clear(in featureModel: OmniBarFeatureModel)
}

@MainActor
protocol OmniBarPanelProviding: OmniBarModule {
    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor?
    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool
}

@MainActor
protocol OmniBarSelectableResultsProviding: OmniBarModule, ListSelectable {}

@MainActor
protocol OmniBarMentionProviding: OmniBarModule {
    var mentionSuggestionsViewModel: MentionSuggestionsViewModel { get }
    func handleMentionTrigger(query: String, in featureModel: OmniBarFeatureModel)
    func handleMentionSelection(in featureModel: OmniBarFeatureModel)
    func selectMentionSuggestion(_ suggestion: MentionSuggestion, in featureModel: OmniBarFeatureModel)
    func dismissMentionSuggestions(in featureModel: OmniBarFeatureModel)
}

@MainActor
protocol OmniBarAccessoryProviding: OmniBarModule {
    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView?
}

@MainActor
struct OmniBarModuleRegistry {
    let modules: [any OmniBarModule]
    private let modulesByID: [OmniBarModuleID: any OmniBarModule]

    init(modules: [any OmniBarModule]) {
        self.modules = modules
        self.modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
    }

    var orderedModuleIDs: [OmniBarModuleID] {
        modules.map(\.id).filter(BrowserExperience.showsOmniBarModule)
    }

    func module(for id: OmniBarModuleID) -> (any OmniBarModule)? {
        modulesByID[id]
    }

    func module<M: OmniBarModule>(for id: OmniBarModuleID, as type: M.Type) -> M? {
        modulesByID[id] as? M
    }

    func nextID(after id: OmniBarModuleID) -> OmniBarModuleID {
        guard let currentIndex = orderedModuleIDs.firstIndex(of: id) else {
            return orderedModuleIDs.first ?? .address
        }

        let nextIndex = orderedModuleIDs.index(after: currentIndex)
        return nextIndex < orderedModuleIDs.endIndex ? orderedModuleIDs[nextIndex] : orderedModuleIDs[orderedModuleIDs.startIndex]
    }

    func previousID(before id: OmniBarModuleID) -> OmniBarModuleID {
        guard let currentIndex = orderedModuleIDs.firstIndex(of: id) else {
            return orderedModuleIDs.first ?? .address
        }

        if currentIndex == orderedModuleIDs.startIndex {
            return orderedModuleIDs[orderedModuleIDs.index(before: orderedModuleIDs.endIndex)]
        }
        return orderedModuleIDs[orderedModuleIDs.index(before: currentIndex)]
    }

    static func builtIn() -> Self {
        Self(modules: [
            AddressOmniBarModule(),
            ChatOmniBarModule(),
            SemanticOmniBarModule(),
            AgentOmniBarModule(),
            ReadingListOmniBarModule(),
        ])
    }
}

private struct OmniBarClearInputButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale))
    }
}

@MainActor
final class AddressOmniBarModule: OmniBarPanelProviding, OmniBarSelectableResultsProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .address
    let title = "Go to"
    let icon = "magnifyingglass"
    let placeholder = "Search or enter URL"
    let color: Color = .accentColor
    let inputKind: OmniBarInputKind = .singleLine

    let viewModel = SuggestionsViewModel()

    var selectedIndex: Int {
        get { viewModel.selectedIndex }
        set { viewModel.selectedIndex = newValue }
    }

    var selectableCount: Int {
        viewModel.selectableCount
    }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        if featureModel.inputText.isEmpty {
            viewModel.loadRecentHistory()
        } else {
            viewModel.updateSuggestions(for: featureModel.inputText)
        }

        if !featureModel.isInputFocused && reason == .focusGain {
            return
        }
        featureModel.setVisiblePanel(.history)
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        viewModel.hide()
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
        if text.isEmpty {
            viewModel.loadRecentHistory()
        } else {
            viewModel.updateSuggestions(for: text)
        }
    }

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        guard !featureModel.tab.showsChatUI else { return }

        if let selected = viewModel.selectedSuggestion {
            featureModel.handleSuggestionSelection(selected)
            return
        }

        featureModel.tab.load(featureModel.inputText)
        featureModel.isInputFocused = false
        viewModel.hide()
        featureModel.dismissVisiblePanel()
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
        viewModel.clear()
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        false
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: .blue,
            subtitle: featureModel.historyPanelSubtitle,
            menuContent: nil,
            content: AnyView(
                HistoryPanelContent(
                    viewModel: viewModel,
                    searchText: featureModel.inputText,
                    onSelect: { [weak featureModel] suggestion in
                        featureModel?.handleSuggestionSelection(suggestion)
                    }
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        guard featureModel.isInputFocused, !featureModel.inputText.isEmpty else { return nil }
        return AnyView(OmniBarClearInputButton { [weak featureModel] in
            featureModel?.inputText = ""
            self.viewModel.clear()
        })
    }
}

@MainActor
final class ChatOmniBarModule: OmniBarPanelProviding, OmniBarMentionProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .chat
    let title = "Chat"
    let icon = "sparkles"
    let placeholder = "Ask about this page..."
    let color: Color = .purple
    let inputKind: OmniBarInputKind = .multiLine

    let mentionSuggestionsViewModel = MentionSuggestionsViewModel()

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        if reason != .focusGain, featureModel.tab.url == nil {
            featureModel.removeMention(.currentPage, userInitiated: false)
        }

        if featureModel.isFullPageChatActiveOrPending {
            featureModel.dismissVisiblePanel()
            return
        }

        if OmniBarChatPanelVisibilityPolicy.shouldShowFloatingPanel(
            isSending: featureModel.isSending,
            isLoading: featureModel.agentManager.isLoading,
            isStreaming: featureModel.agentManager.isStreamingActive,
            hasMessages: !featureModel.agentManager.messages.isEmpty,
            isFullPageChatActiveOrPending: false
        ) {
            featureModel.setVisiblePanel(.chat)
        } else {
            featureModel.dismissVisiblePanel()
        }
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        dismissMentionSuggestions(in: featureModel)
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {}

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        let content = featureModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let currentMentions = featureModel.mentions
        if featureModel.tab.isChatTab && !featureModel.tab.hasConversationStarted {
            featureModel.tab.hasConversationStarted = true
        }

        featureModel.inputText = ""
        featureModel.isSending = true
        featureModel.setVisiblePanel(.chat)

        Task { [weak featureModel] in
            guard let featureModel else { return }

            let resolver = MentionContentResolver(
                contentExtractor: featureModel.contentExtractor,
                browserState: featureModel.browserState,
                currentTab: featureModel.tab,
                fabricClient: featureModel.fabricClient
            )
            let pageContexts = await resolver.resolve(mentions: currentMentions, query: content)

            await featureModel.agentManager.sendMessage(content, pageContexts: pageContexts)
            featureModel.isSending = false
            featureModel.resetMentions(includeCurrentPage: featureModel.tab.url != nil)
        }
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        switch command {
        case .moveUp:
            guard featureModel.showMentionDropdown else { return nil }
            mentionSuggestionsViewModel.selectPrevious()
            return true
        case .moveDown:
            guard featureModel.showMentionDropdown else { return nil }
            mentionSuggestionsViewModel.selectNext()
            return true
        case .submit:
            if featureModel.showMentionDropdown && !mentionSuggestionsViewModel.suggestions.isEmpty {
                handleMentionSelection(in: featureModel)
            } else {
                handleSubmit(in: featureModel)
            }
            return true
        case .escape:
            if featureModel.showMentionDropdown {
                dismissMentionSuggestions(in: featureModel)
            } else {
                featureModel.handleEscapePressed()
            }
            return true
        case .deleteBackward:
            if text.isEmpty, let lastMention = featureModel.mentions.last {
                featureModel.removeMention(lastMention)
                return true
            }
            return false
        case .tab, .shiftTab:
            return nil
        }
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        guard featureModel.mode == id else { return false }
        return OmniBarChatPanelVisibilityPolicy.shouldShowFloatingPanel(
            isSending: featureModel.isSending,
            isLoading: featureModel.agentManager.isLoading,
            isStreaming: featureModel.agentManager.isStreamingActive,
            hasMessages: !featureModel.agentManager.messages.isEmpty,
            isFullPageChatActiveOrPending: featureModel.isFullPageChatActiveOrPending
        )
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id), !featureModel.isFullPageChatActive else { return nil }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: "Chat",
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: color,
            borderColor: color,
            subtitle: featureModel.isSending || featureModel.agentManager.isLoading ? "Thinking..." : nil,
            menuContent: AnyView(
                Group {
                    Button("Clear Chat") {
                        featureModel.agentManager.clearMessages()
                    }
                    Divider()
                    Button("Reset Agent", role: .destructive) {
                        Task { await featureModel.agentManager.resetAgent() }
                    }
                }
            ),
            content: AnyView(
                ChatPanelContent(
                    agentManager: featureModel.agentManager,
                    isSending: featureModel.isSending,
                    onSubmitPrompt: { [weak featureModel] text in
                        featureModel?.inputText = text
                    }
                )
            )
        )
    }

    func handleMentionTrigger(query: String, in featureModel: OmniBarFeatureModel) {
        if !featureModel.showMentionDropdown {
            featureModel.openMentionDropdown()
        }
        featureModel.mentionSearchText = query
        mentionSuggestionsViewModel.updateSuggestions(
            for: query,
            excluding: featureModel.mentions,
            currentTabId: featureModel.tab.id
        )
    }

    func handleMentionSelection(in featureModel: OmniBarFeatureModel) {
        guard let suggestion = mentionSuggestionsViewModel.selectedSuggestion else { return }
        selectMentionSuggestion(suggestion, in: featureModel)
    }

    func selectMentionSuggestion(_ suggestion: MentionSuggestion, in featureModel: OmniBarFeatureModel) {
        withAnimation(AppAnimation.standard) {
            featureModel.addMention(suggestion.mention)
            featureModel.dismissMentionDropdown()
        }
        mentionSuggestionsViewModel.clear()
        featureModel.removeAtQueryFromInput()
    }

    func dismissMentionSuggestions(in featureModel: OmniBarFeatureModel) {
        if featureModel.showMentionDropdown {
            featureModel.dismissMentionDropdown()
        }
        mentionSuggestionsViewModel.clear()
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        AnyView(
            ChatModeActionButton(
                agentManager: featureModel.agentManager,
                inputText: featureModel.inputText,
                isSending: featureModel.isSending,
                onSubmit: { [weak featureModel] in
                    featureModel?.handleSubmit()
                }
            )
        )
    }
}

@MainActor
final class SemanticOmniBarModule: OmniBarPanelProviding, OmniBarSelectableResultsProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .semantic
    let title = "Semantic Search"
    let icon = "brain.head.profile"
    let placeholder = "Search history semantically..."
    let color: Color = .orange
    let inputKind: OmniBarInputKind = .singleLine

    let viewModel = SemanticSearchViewModel()

    var selectedIndex: Int {
        get { viewModel.selectedIndex }
        set { viewModel.selectedIndex = newValue }
    }

    var selectableCount: Int {
        viewModel.selectableCount
    }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        if !featureModel.inputText.isEmpty {
            viewModel.search(query: featureModel.inputText)
        }
        featureModel.setVisiblePanel(.semantic)
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        viewModel.clear()
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
        viewModel.search(query: text)
    }

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        guard let selected = viewModel.selectedResult else { return }
        featureModel.handleSemanticSelection(selected)
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
        viewModel.clear()
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        featureModel.mode == id && !viewModel.results.isEmpty
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        let searchManager = SemanticSearchManagerV2.shared
        let subtitle: String
        if viewModel.isSearching {
            subtitle = "Searching..."
        } else if !viewModel.results.isEmpty {
            subtitle = "\(viewModel.results.count) results"
        } else {
            subtitle = "\(searchManager.stats.pageCount) pages indexed"
        }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: color,
            subtitle: subtitle,
            menuContent: AnyView(
                Button("Clear Index") {
                    Task { await searchManager.clearIndex() }
                }
            ),
            content: AnyView(
                SemanticSearchPanelContent(
                    viewModel: viewModel,
                    searchManager: searchManager,
                    searchText: featureModel.inputText,
                    onSelect: { [weak featureModel] result in
                        featureModel?.handleSemanticSelection(result)
                    }
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        guard featureModel.isInputFocused, !featureModel.inputText.isEmpty else { return nil }
        return AnyView(OmniBarClearInputButton { [weak featureModel] in
            featureModel?.inputText = ""
            self.viewModel.clear()
        })
    }
}

@MainActor
final class AgentOmniBarModule: OmniBarPanelProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .agent
    let title = "Agent"
    let icon = "wand.and.stars"
    let placeholder = "Describe a task for the agent..."
    let color: Color = .green
    let inputKind: OmniBarInputKind = .singleLine

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        featureModel.dismissVisiblePanel()
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {}

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {}

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        let task = featureModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        featureModel.inputText = ""
        featureModel.dismissVisiblePanel()

        Task {
            _ = await featureModel.agentEngine.run(task: task)
        }
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        featureModel.mode == id && (!featureModel.agentEngine.steps.isEmpty || featureModel.agentEngine.isRunning)
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        let subtitle: String
        if featureModel.agentEngine.isRunning {
            subtitle = featureModel.agentEngine.progress
        } else if !featureModel.agentEngine.steps.isEmpty {
            if let lastStep = featureModel.agentEngine.steps.last, lastStep.type == .done {
                subtitle = "Completed"
            } else if featureModel.agentEngine.error != nil {
                subtitle = "Failed"
            } else {
                subtitle = "\(featureModel.agentEngine.steps.count) steps"
            }
        } else {
            subtitle = "Ready"
        }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: color,
            subtitle: subtitle,
            menuContent: AnyView(
                Group {
                    Button("Cancel Task") { featureModel.agentEngine.cancel() }
                        .disabled(!featureModel.agentEngine.isRunning)
                    Divider()
                    Button("Clear History") { featureModel.agentEngine.clearHistory() }
                        .disabled(featureModel.agentEngine.steps.isEmpty && featureModel.agentEngine.lastResult == nil)
                }
            ),
            content: AnyView(
                AgentPanelContent(
                    agentEngine: featureModel.agentEngine,
                    browserState: featureModel.browserState
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        AnyView(
            AgentActionButton(
                agentEngine: featureModel.agentEngine,
                inputText: featureModel.inputText,
                onSubmit: { [weak featureModel] in
                    featureModel?.handleSubmit()
                }
            )
        )
    }
}

@MainActor
final class ReadingListOmniBarModule: OmniBarPanelProviding, OmniBarSelectableResultsProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .readingList
    let title = "Reading List"
    let icon = "bookmark.fill"
    let placeholder = "Search reading list..."
    let color: Color = .pink
    let inputKind: OmniBarInputKind = .singleLine

    let viewModel = ReadingListViewModel()

    var selectedIndex: Int {
        get { viewModel.selectedIndex }
        set { viewModel.selectedIndex = newValue }
    }

    var selectableCount: Int {
        viewModel.selectableCount
    }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        viewModel.loadSavedPages()
        featureModel.setVisiblePanel(.readingList)
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        viewModel.clear()
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
        viewModel.search(query: text)
    }

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        guard let selected = viewModel.selectedItem else { return }
        featureModel.handleReadingListSelection(selected)
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
        viewModel.loadSavedPages()
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        featureModel.mode == id && !viewModel.items.isEmpty
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        let subtitle: String?
        if viewModel.isLoading {
            subtitle = "Loading..."
        } else if !viewModel.items.isEmpty {
            subtitle = "\(viewModel.items.count) saved"
        } else {
            subtitle = nil
        }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: color,
            subtitle: subtitle,
            menuContent: nil,
            content: AnyView(
                ReadingListPanelContent(
                    viewModel: viewModel,
                    searchText: featureModel.inputText,
                    onSelect: { [weak featureModel] item in
                        featureModel?.handleReadingListSelection(item)
                    }
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        guard featureModel.isInputFocused, !featureModel.inputText.isEmpty else { return nil }
        return AnyView(OmniBarClearInputButton { [weak featureModel] in
            featureModel?.inputText = ""
            self.viewModel.loadSavedPages()
        })
    }
}
