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
            suggestionsVM.hide()
            semanticSearchVM.clear()
            readingListVM.clear()
            if omniState.mode == .address {
                omniState.dismissHistoryPanel()
            } else if omniState.mode == .semantic {
                omniState.dismissSemanticPanel()
            } else if omniState.mode == .readingList {
                omniState.dismissReadingListPanel()
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
        switch newMode {
        case .chat:
            suggestionsVM.hide()
            semanticSearchVM.clear()
            readingListVM.clear()
            omniState.dismissHistoryPanel()
            omniState.dismissSemanticPanel()
            omniState.dismissAgentPanel()
            omniState.dismissReadingListPanel()
            omniState.dismissScrapingPanel()
            // Remove current page mention if on new tab (no URL)
            if tab.url == nil {
                omniState.removeMention(.currentPage)
            }
            if !agentManager.messages.isEmpty {
                omniState.openChatPanel()
            }
        case .address:
            semanticSearchVM.clear()
            readingListVM.clear()
            omniState.dismissChatPanel()
            omniState.dismissSemanticPanel()
            omniState.dismissAgentPanel()
            omniState.dismissReadingListPanel()
            omniState.dismissScrapingPanel()
            if isInputFocused {
                omniState.openHistoryPanel()
            }
        case .semantic:
            suggestionsVM.hide()
            readingListVM.clear()
            omniState.dismissChatPanel()
            omniState.dismissHistoryPanel()
            omniState.dismissAgentPanel()
            omniState.dismissReadingListPanel()
            omniState.dismissScrapingPanel()
            omniState.openSemanticPanel()
            if !omniState.inputText.isEmpty {
                semanticSearchVM.search(query: omniState.inputText)
            }
        case .agent:
            suggestionsVM.hide()
            semanticSearchVM.clear()
            readingListVM.clear()
            omniState.dismissChatPanel()
            omniState.dismissHistoryPanel()
            omniState.dismissSemanticPanel()
            omniState.dismissReadingListPanel()
            omniState.dismissScrapingPanel()
            omniState.openAgentPanel()
        case .readingList:
            suggestionsVM.hide()
            semanticSearchVM.clear()
            omniState.dismissChatPanel()
            omniState.dismissHistoryPanel()
            omniState.dismissSemanticPanel()
            omniState.dismissAgentPanel()
            omniState.dismissScrapingPanel()
            omniState.openReadingListPanel()
            readingListVM.loadSavedPages()
        case .scraping:
            suggestionsVM.hide()
            semanticSearchVM.clear()
            readingListVM.clear()
            omniState.dismissChatPanel()
            omniState.dismissHistoryPanel()
            omniState.dismissSemanticPanel()
            omniState.dismissAgentPanel()
            omniState.dismissReadingListPanel()
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
        withAnimation(.easeInOut(duration: 0.15)) {
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

    // MARK: - Page Save State Changed

    func handlePageSaveStateChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let url = userInfo["url"] as? String,
           let isSaved = userInfo["isSaved"] as? Bool,
           url == tab.url?.absoluteString {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCurrentPageSaved = isSaved
            }
        }
    }
}
