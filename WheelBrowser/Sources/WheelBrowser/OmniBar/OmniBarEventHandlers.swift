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
        activateMode(omniState.mode, isFocusGain: true)
    }

    // MARK: - Mode Change

    func handleModeChange(_ newMode: OmniBarMode) {
        // Clear search state for VMs not owned by the new mode
        clearSearchState(except: newMode)

        // Dismiss any currently visible panel
        omniState.dismissVisiblePanel()

        activateMode(newMode, isFocusGain: false)
    }

    /// Shared mode activation logic for both focus gain and mode change.
    /// - Parameters:
    ///   - mode: The mode to activate
    ///   - isFocusGain: `true` when called from focus gain (chat skips panel open), `false` from mode change
    private func activateMode(_ mode: OmniBarMode, isFocusGain: Bool) {
        switch mode {
        case .address:
            if !isFocusGain || isInputFocused {
                omniState.setVisiblePanel(.history)
            }
            if omniState.inputText.isEmpty {
                suggestionsVM.loadRecentHistory()
            } else {
                suggestionsVM.updateSuggestions(for: omniState.inputText)
            }
        case .chat:
            if !isFocusGain {
                if tab.url == nil {
                    omniState.removeMention(.currentPage)
                }
            }
            if !agentManager.messages.isEmpty {
                omniState.setVisiblePanel(.chat)
            }
        case .semantic:
            omniState.setVisiblePanel(.semantic)
            if !omniState.inputText.isEmpty {
                semanticSearchVM.search(query: omniState.inputText)
            }
        case .agent:
            omniState.setVisiblePanel(.agent)
        case .readingList:
            omniState.setVisiblePanel(.readingList)
            readingListVM.loadSavedPages()
        case .scraping:
            omniState.setVisiblePanel(.scraping)
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
        } else if omniState.visiblePanel != .none {
            dismissCurrentPanel()
        } else if isInputFocused {
            isInputFocused = false
            if omniState.mode == .address {
                omniState.inputText = tab.url?.absoluteString ?? ""
            } else {
                omniState.inputText = ""
            }
        }
    }

    /// Dismiss the currently visible panel with mode-specific cleanup
    private func dismissCurrentPanel() {
        let panel = omniState.visiblePanel
        omniState.dismissVisiblePanel()
        isInputFocused = false

        switch panel {
        case .history:
            omniState.inputText = tab.url?.absoluteString ?? ""
        case .chat:
            break // Chat preserves input
        case .scraping:
            if omniState.mode == .scraping {
                omniState.mode = .address
            }
            omniState.inputText = ""
        case .semantic, .agent, .readingList, .downloads:
            omniState.inputText = ""
        case .none:
            break
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
            omniState.setVisiblePanel(.chat)
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
        omniState.setVisiblePanel(.semantic)
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
        omniState.setVisiblePanel(.readingList)
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

// MARK: - OmniBarKeyboardHandler Conformance

extension OmniBar: OmniBarKeyboardHandler {
    func handleKeyboardCommand(_ command: KeyboardCommand, mode: OmniBarMode, text: String) -> Bool {
        // Chat mode has special mention-aware keyboard handling
        if mode == .chat {
            if let result = handleChatKeyboardCommand(command, text: text) {
                return result
            }
        }
        return handleGeneralKeyboardCommand(command, mode: mode)
    }

    /// Chat mode keyboard handling. Returns `true` if handled, `false` if not handled,
    /// `nil` if chat mode didn't claim it and general handling should proceed.
    private func handleChatKeyboardCommand(_ command: KeyboardCommand, text: String) -> Bool? {
        switch command {
        case .moveUp:
            // Only swallow arrow keys when mention dropdown is open
            guard omniState.showMentionDropdown else { return nil }
            mentionSuggestionsVM.selectPrevious()
            return true

        case .moveDown:
            guard omniState.showMentionDropdown else { return nil }
            mentionSuggestionsVM.selectNext()
            return true

        case .submit:
            if omniState.showMentionDropdown && !mentionSuggestionsVM.suggestions.isEmpty {
                handleMentionSelection()
            } else {
                handleSubmit()
            }
            return true

        case .escape:
            if omniState.showMentionDropdown {
                omniState.dismissMentionDropdown()
                mentionSuggestionsVM.clear()
            } else {
                NotificationCenter.default.post(name: .escapePressed, object: nil)
            }
            return true

        case .deleteBackward:
            if text.isEmpty {
                if let lastMention = omniState.mentions.last {
                    omniState.removeMention(lastMention)
                }
                return true
            }
            return false

        case .tab, .shiftTab:
            return nil
        }
    }

    /// General keyboard handling shared across all modes.
    private func handleGeneralKeyboardCommand(_ command: KeyboardCommand, mode: OmniBarMode) -> Bool {
        switch command {
        case .submit:
            handleSubmit()
            return true

        case .moveUp:
            switch mode {
            case .address: suggestionsVM.selectPrevious()
            case .semantic: semanticSearchVM.selectPrevious()
            case .readingList: readingListVM.selectPrevious()
            case .chat, .agent, .scraping: return false
            }
            return true

        case .moveDown:
            switch mode {
            case .address: suggestionsVM.selectNext()
            case .semantic: semanticSearchVM.selectNext()
            case .readingList: readingListVM.selectNext()
            case .chat, .agent, .scraping: return false
            }
            return true

        case .tab:
            let wasChat = omniState.mode == .chat
            omniState.nextMode()
            if !wasChat && omniState.mode == .chat {
                omniState.resetMentions(includeCurrentPage: tab.url != nil)
            }
            return true

        case .shiftTab:
            let wasChat = omniState.mode == .chat
            omniState.previousMode()
            if !wasChat && omniState.mode == .chat {
                omniState.resetMentions(includeCurrentPage: tab.url != nil)
            }
            return true

        case .escape:
            NotificationCenter.default.post(name: .escapePressed, object: nil)
            return true

        case .deleteBackward:
            return false
        }
    }
}
