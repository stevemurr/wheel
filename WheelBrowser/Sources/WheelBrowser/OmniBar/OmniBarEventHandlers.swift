import SwiftUI

// MARK: - onChange / onReceive Event Handler Methods

extension OmniBar {
    // MARK: - URL Change

    func handleURLChange(_ newURL: URL?) {
        if !isInputFocused && omniState.mode == .address {
            omniState.inputText = newURL?.absoluteString ?? ""
        }
        Task {
            await checkIfCurrentPageIsSaved()
        }
    }

    // MARK: - Input Text Change

    func handleInputTextChange(_ newValue: String) {
        guard isInputFocused else { return }
        switch omniState.mode {
        case .address:
            if newValue.isEmpty {
                suggestionsVM.loadRecentHistory()
            } else {
                suggestionsVM.updateSuggestions(for: newValue)
            }
        case .semantic:
            semanticSearchVM.search(query: newValue)
        case .readingList:
            readingListVM.search(query: newValue)
        case .chat, .agent, .scraping:
            break
        }
    }

    // MARK: - Focus Change

    func handleFocusChange(_ focused: Bool) {
        omniState.isFocused = focused
        if !focused {
            handleFocusLost()
        } else {
            handleFocusGained()
        }
    }

    private func handleFocusLost() {
        // Delay hiding to allow click on suggestion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.clearAllSearchState()
            if self.omniState.mode == .address || self.omniState.mode == .semantic || self.omniState.mode == .readingList {
                self.omniState.dismissVisiblePanel()
            }
        }
    }

    private func handleFocusGained() {
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
        case .readingList:
            omniState.openReadingListPanel()
            readingListVM.loadSavedPages()
        case .chat:
            break
        case .agent:
            omniState.openAgentPanel()
        case .scraping:
            omniState.openScrapingPanel()
        }
    }

    // MARK: - Mode Change

    func handleModeChange(_ newMode: OmniBarMode) {
        // Clear search state for VMs not owned by the new mode
        clearSearchState(except: newMode)

        // Dismiss any currently visible panel
        omniState.dismissVisiblePanel()

        // Mode-specific setup
        switch newMode {
        case .chat:
            if tab.url == nil {
                omniState.removeMention(.currentPage)
            }
            if !agentManager.messages.isEmpty {
                omniState.openChatPanel()
            }
        case .address:
            if isInputFocused {
                omniState.openHistoryPanel()
            }
        case .semantic:
            omniState.openSemanticPanel()
            if !omniState.inputText.isEmpty {
                semanticSearchVM.search(query: omniState.inputText)
            }
        case .agent:
            omniState.openAgentPanel()
        case .readingList:
            omniState.openReadingListPanel()
            readingListVM.loadSavedPages()
        case .scraping:
            omniState.openScrapingPanel()
        }
    }

    // MARK: - Escape Pressed

    func handleEscapePressed() {
        if downloadManager.showDownloadsPanel {
            downloadManager.dismissPanel()
        } else if omniState.showMentionDropdown {
            omniState.dismissMentionDropdown()
            mentionSuggestionsVM.clear()
        } else if tab.isFindBarVisible {
            withAnimation(AppAnimation.standard) {
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
        } else if omniState.showReadingListPanel {
            omniState.dismissReadingListPanel()
            isInputFocused = false
            omniState.inputText = ""
        } else if omniState.showScrapingPanel || scrapeManager.showScrapePanel {
            omniState.dismissScrapingPanel()
            scrapeManager.dismissPanel()
            if omniState.mode == .scraping {
                omniState.mode = .address
            }
            isInputFocused = false
            omniState.inputText = ""
        } else if isInputFocused {
            isInputFocused = false
            if omniState.mode == .address {
                omniState.inputText = tab.url?.absoluteString ?? ""
            } else if omniState.mode == .semantic || omniState.mode == .agent || omniState.mode == .readingList || omniState.mode == .scraping {
                omniState.inputText = ""
            }
        }
    }

    // MARK: - Focus Address Bar

    func handleFocusAddressBar() {
        omniState.setMode(.address)
        isInputFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.keyWindow,
               let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
                fieldEditor.selectAll(nil)
            }
        }
    }

    // MARK: - Focus AI Sidebar

    func handleFocusAISidebar() {
        omniState.setMode(.chat)
        isInputFocused = true
        omniState.resetMentions(includeCurrentPage: tab.url != nil)
        if !agentManager.messages.isEmpty {
            omniState.openChatPanel()
        }
    }

    // MARK: - Focus Chat Input

    func handleFocusChatInput() {
        omniState.setMode(.chat)
        isInputFocused = true
        omniState.resetMentions(includeCurrentPage: tab.url != nil)
    }

    // MARK: - Focus Semantic Search

    func handleFocusSemanticSearch() {
        omniState.setMode(.semantic)
        isInputFocused = true
        omniState.openSemanticPanel()
    }

    // MARK: - Find in Page

    func handleFindInPage() {
        withAnimation(AppAnimation.standard) {
            tab.showFindBar()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isFindFieldFocused = true
        }
    }

    // MARK: - Focus Reading List

    func handleFocusReadingList() {
        omniState.setMode(.readingList)
        isInputFocused = true
        omniState.openReadingListPanel()
        readingListVM.loadSavedPages()
    }

    // MARK: - Search State Helpers

    /// Clear all search view model state (suggestions, semantic, reading list)
    private func clearAllSearchState() {
        suggestionsVM.hide()
        semanticSearchVM.clear()
        readingListVM.clear()
    }

    /// Clear search state for VMs not owned by the target mode.
    /// Each mode keeps its own VM active to avoid clearing state that's about to be used.
    private func clearSearchState(except mode: OmniBarMode) {
        if mode != .address { suggestionsVM.hide() }
        if mode != .semantic { semanticSearchVM.clear() }
        if mode != .readingList { readingListVM.clear() }
    }

    // MARK: - Page Save State Changed

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
}
