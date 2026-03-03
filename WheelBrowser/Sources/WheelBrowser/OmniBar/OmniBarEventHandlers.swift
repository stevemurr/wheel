import SwiftUI

// MARK: - onChange / onReceive Event Handler Methods

extension OmniBar {
    // MARK: - Full Page Chat State

    /// Updates `agentManager.isFullPageChatActive` based on current tab URL and mode.
    /// Called BEFORE `setVisiblePanel` to ensure non-animated state changes precede
    /// animated panel transitions (Rule 8). Does NOT use `withAnimation`.
    ///
    /// Once an empty tab enters chat mode, `tab.isChatTab` latches to `true`
    /// and the tab permanently shows `FullPageChatView`. Mode cycling and
    /// escape-to-address are blocked elsewhere when this flag is set.
    func updateFullPageChatState() {
        // One-way latch: once a tab becomes a chat tab, it stays that way
        if tab.url == nil && omniState.mode == .chat && !tab.isChatTab {
            tab.isChatTab = true
        }
        let shouldBeActive = tab.url == nil && tab.isChatTab
        if agentManager.isFullPageChatActive != shouldBeActive {
            agentManager.isFullPageChatActive = shouldBeActive
        }
    }

    // MARK: - URL Change

    func handleURLChange(_ newURL: URL?) {
        updateFullPageChatState()
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
        // NOTE: Do NOT set omniState.isFocused here — it is @Published and fires
        // objectWillChange without an animation context, creating a non-animated
        // body re-eval that interleaves with the animated panel transition below.
        if !focused {
            handleFocusLost()
        } else {
            handleFocusGained()
        }
    }

    private func handleFocusLost() {
        // Delay hiding to allow click on suggestion.
        // IMPORTANT: Check isInputFocused inside the delayed block to avoid
        // dismissing a panel that was re-opened by a focus-regain within the delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !self.isInputFocused else { return }
            self.clearAllSearchState()
            if self.omniState.mode == .address || self.omniState.mode == .semantic || self.omniState.mode == .readingList {
                self.omniState.dismissVisiblePanel()
            }
        }
    }

    private func handleFocusGained() {
        updateFullPageChatState()
        activateMode(omniState.mode, isFocusGain: true)
    }

    // MARK: - Mode Change

    func handleModeChange(_ newMode: OmniBarMode) {
        // Clear search state for VMs not owned by the new mode
        clearSearchState(except: newMode)

        // Update full-page chat flag before any panel changes (Rule 8)
        updateFullPageChatState()

        // Skip panel activation when input is unfocused (e.g. during Escape dismissal).
        // Just dismiss any visible panel and return.
        guard isInputFocused else {
            omniState.dismissVisiblePanel()
            return
        }

        // Activate the new mode in a single animation transaction.
        // Do NOT dismiss first then activate — that creates two competing
        // withAnimation blocks, briefly showing visiblePanel = .none (flash).
        activateMode(newMode, isFocusGain: false)
    }

    /// Shared mode activation logic for both focus gain and mode change.
    ///
    /// IMPORTANT: Non-animated state changes (loading suggestions, removing mentions, etc.)
    /// must happen BEFORE setVisiblePanel(). This ensures their objectWillChange signals
    /// fire before the animated panel transition, preventing non-animated body re-evals
    /// from interleaving with the panel animation.
    ///
    /// - Parameters:
    ///   - mode: The mode to activate
    ///   - isFocusGain: `true` when called from focus gain (chat skips panel open), `false` from mode change
    private func activateMode(_ mode: OmniBarMode, isFocusGain: Bool) {
        switch mode {
        case .address:
            // Load suggestions first (non-animated state changes)
            if omniState.inputText.isEmpty {
                suggestionsVM.loadRecentHistory()
            } else {
                suggestionsVM.updateSuggestions(for: omniState.inputText)
            }
            // Show panel last (animated)
            if !isFocusGain || isInputFocused {
                omniState.setVisiblePanel(.history)
            }
        case .chat:
            // Non-animated state changes first
            if !isFocusGain {
                if tab.url == nil {
                    omniState.removeMention(.currentPage)
                }
            }
            // Show panel last (animated)
            if !agentManager.messages.isEmpty {
                omniState.setVisiblePanel(.chat)
            } else {
                // Dismiss any stale panel from the previous mode (e.g. history
                // panel left over when an empty tab converts to chat).
                omniState.dismissVisiblePanel()
            }
        case .semantic:
            // Non-animated state changes first
            if !omniState.inputText.isEmpty {
                semanticSearchVM.search(query: omniState.inputText)
            }
            // Show panel last (animated)
            omniState.setVisiblePanel(.semantic)
        case .agent:
            omniState.setVisiblePanel(.agent)
        case .readingList:
            readingListVM.loadSavedPages()
            omniState.setVisiblePanel(.readingList)
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
        updateFullPageChatState()

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
        // Chat tabs are locked to chat mode
        guard !agentManager.isFullPageChatActive else { return }
        // Set focus BEFORE mode so that handleModeChange sees isInputFocused=true
        // and activates the panel directly, instead of dismissing then re-showing (flash).
        // No withAnimation — pill expansion is driven by the implicit .animation() on
        // omniBarContent, and panel transitions by setVisiblePanel()'s own withAnimation.
        isInputFocused = true
        omniState.setMode(.address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.keyWindow,
               let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
                fieldEditor.selectAll(nil)
            }
        }
    }

    // MARK: - Focus AI Sidebar

    func handleFocusAISidebar() {
        // Set focus BEFORE mode — see handleFocusAddressBar for why.
        // No withAnimation — see handleFocusAddressBar for why.
        isInputFocused = true
        omniState.resetMentions(includeCurrentPage: tab.url != nil)
        omniState.setMode(.chat)
        // NOTE: Do NOT call setVisiblePanel here — setMode triggers
        // handleModeChange → activateMode which already calls setVisiblePanel.
    }

    // MARK: - Focus Chat Input

    func handleFocusChatInput() {
        // No withAnimation — see handleFocusAddressBar for why.
        isInputFocused = true
        omniState.resetMentions(includeCurrentPage: tab.url != nil)
        omniState.setMode(.chat)
    }

    // MARK: - Focus Semantic Search

    func handleFocusSemanticSearch() {
        guard !agentManager.isFullPageChatActive else { return }
        // No withAnimation — see handleFocusAddressBar for why.
        isInputFocused = true
        omniState.setMode(.semantic)
        // NOTE: Do NOT call setVisiblePanel here — handled by setMode → handleModeChange → activateMode.
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
        guard !agentManager.isFullPageChatActive else { return }
        // No withAnimation — see handleFocusAddressBar for why.
        isInputFocused = true
        omniState.setMode(.readingList)
        // NOTE: Do NOT call setVisiblePanel here — handled by setMode → handleModeChange → activateMode.
        // readingListVM.loadSavedPages() is called inside activateMode.
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
            // Block mode cycling on chat tabs
            guard !agentManager.isFullPageChatActive else { return true }
            let wasChat = omniState.mode == .chat
            omniState.nextMode()
            if !wasChat && omniState.mode == .chat {
                omniState.resetMentions(includeCurrentPage: tab.url != nil)
            }
            return true

        case .shiftTab:
            guard !agentManager.isFullPageChatActive else { return true }
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
