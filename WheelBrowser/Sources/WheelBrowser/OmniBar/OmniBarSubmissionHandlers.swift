import SwiftUI

// MARK: - Submission Handlers

extension OmniBar {
    func handleSubmit() {
        switch omniState.mode {
        case .address:
            submitAddress()
        case .chat:
            submitChat()
        case .semantic:
            submitSemantic()
        case .agent:
            submitAgent()
        case .readingList:
            submitReadingList()
        }
    }

    func submitAddress() {
        guard !tab.isChatTab else { return }
        if let selected = suggestionsVM.selectedSuggestion {
            handleSuggestionSelection(selected)
            return
        }
        tab.load(omniState.inputText)
        isInputFocused = false
        suggestionsVM.hide()
        omniState.dismissVisiblePanel()
    }

    func handleSuggestionSelection(_ suggestion: Suggestion) {
        switch suggestion {
        case .openTab(let tab, _, _, _):
            browserState.selectTab(tab.id)
            isInputFocused = false
            omniState.dismissVisiblePanel()
            suggestionsVM.hide()
            omniState.inputText = tab.url?.absoluteString ?? ""

        case .history(let entry, _, _, _):
            guard !tab.isChatTab else { return }
            omniState.inputText = entry.url
            self.tab.load(entry.url)
            isInputFocused = false
            omniState.dismissVisiblePanel()
            suggestionsVM.hide()
        }
    }

    func submitChat() {
        let content = omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let currentMentions = omniState.mentions
        if tab.isChatTab && !tab.hasConversationStarted {
            tab.hasConversationStarted = true
        }
        omniState.inputText = ""
        isSending = true
        omniState.setVisiblePanel(.chat)

        Task {
            let resolver = MentionContentResolver(
                contentExtractor: contentExtractor,
                browserState: browserState,
                currentTab: tab,
                noteStore: noteStore,
                fabricClient: fabricClient
            )
            let pageContexts = await resolver.resolve(mentions: currentMentions, query: content)

            await agentManager.sendMessage(content, pageContexts: pageContexts)
            isSending = false
            omniState.resetMentions(includeCurrentPage: tab.url != nil)
        }
    }

    func submitSemantic() {
        if let selected = semanticSearchVM.selectedResult {
            handleSemanticSelection(selected)
        }
    }

    func handleSemanticSelection(_ result: SemanticSearchResult) {
        guard !tab.isChatTab else { return }
        tab.load(result.page.url)
        isInputFocused = false
        omniState.dismissVisiblePanel()
        semanticSearchVM.clear()
        omniState.inputText = ""
    }

    func handleReadingListSelection(_ item: SavedPageRecord) {
        guard !tab.isChatTab else { return }
        tab.load(item.url.absoluteString)
        isInputFocused = false
        omniState.dismissVisiblePanel()
        readingListVM.clear()
        omniState.inputText = ""
    }

    func submitAgent() {
        let task = omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        omniState.inputText = ""
        omniState.dismissVisiblePanel()

        Task {
            _ = await agentEngine.run(task: task)
        }
    }

    func submitReadingList() {
        if let selected = readingListVM.selectedItem {
            handleReadingListSelection(selected)
        }
    }
}
