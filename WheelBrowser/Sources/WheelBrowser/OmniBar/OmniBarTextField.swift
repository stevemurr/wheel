import SwiftUI

// MARK: - Custom TextField for OmniBar

struct OmniBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let mode: OmniBarMode
    @ObservedObject var suggestionsVM: SuggestionsViewModel
    @ObservedObject var semanticSearchVM: SemanticSearchViewModel
    @ObservedObject var mentionSuggestionsVM: MentionSuggestionsViewModel
    @ObservedObject var readingListVM: ReadingListViewModel
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

        // Disable macOS text completion to prevent flash on first focus
        textField.isAutomaticTextCompletionEnabled = false
        textField.allowsEditingTextAttributes = false
        if let cell = textField.cell as? NSTextFieldCell {
            cell.isScrollable = true
            cell.usesSingleLineMode = true
        }

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
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.parent.omniState.showMentionDropdown {
                    self.parent.omniState.dismissMentionDropdown()
                    self.parent.mentionSuggestionsVM.clear()
                }
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let command = KeyboardCommand.from(selector: commandSelector) else {
                return false
            }

            // Chat mode has special mention-aware keyboard handling
            if parent.mode == .chat {
                if let result = handleChatModeCommand(command) {
                    return result
                }
            }

            return handleGeneralCommand(command)
        }

        // MARK: - Chat Mode Keyboard Handling

        /// Handles keyboard commands specific to chat mode (mention navigation, backspace to remove mentions).
        /// Returns `true` if handled, `false` if not handled, `nil` if chat mode didn't claim it and general handling should proceed.
        private func handleChatModeCommand(_ command: KeyboardCommand) -> Bool? {
            switch command {
            case .moveUp:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.parent.omniState.showMentionDropdown {
                        self.parent.mentionSuggestionsVM.selectPrevious()
                    }
                }
                return true

            case .moveDown:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.parent.omniState.showMentionDropdown {
                        self.parent.mentionSuggestionsVM.selectNext()
                    }
                }
                return true

            case .submit:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.parent.omniState.showMentionDropdown && !self.parent.mentionSuggestionsVM.suggestions.isEmpty {
                        self.parent.onMentionSelect()
                    } else {
                        self.parent.onSubmit()
                    }
                }
                return true

            case .escape:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.parent.omniState.showMentionDropdown {
                        self.parent.omniState.dismissMentionDropdown()
                        self.parent.mentionSuggestionsVM.clear()
                    } else {
                        NotificationCenter.default.post(name: .escapePressed, object: nil)
                    }
                }
                return true

            case .deleteBackward:
                // If text is empty, try to remove the last mention chip
                if parent.text.isEmpty {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let lastMention = self.parent.omniState.mentions.last {
                            self.parent.omniState.removeMention(lastMention)
                        }
                    }
                    return true
                }
                return false // Let normal backspace behavior happen if text is not empty

            case .tab, .shiftTab:
                // Not claimed by chat mode — fall through to general handling
                return nil
            }
        }

        // MARK: - General Keyboard Handling

        /// Handles keyboard commands shared across all modes (navigation, tab switching, submit, escape).
        private func handleGeneralCommand(_ command: KeyboardCommand) -> Bool {
            switch command {
            case .submit:
                parent.onSubmit()
                return true

            case .moveUp:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch self.parent.mode {
                    case .address:
                        self.parent.suggestionsVM.selectPrevious()
                    case .semantic:
                        self.parent.semanticSearchVM.selectPrevious()
                    case .readingList:
                        self.parent.readingListVM.selectPrevious()
                    case .chat, .agent, .scraping:
                        break
                    }
                }
                switch parent.mode {
                case .address, .semantic, .readingList:
                    return true
                case .chat, .agent, .scraping:
                    return false
                }

            case .moveDown:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch self.parent.mode {
                    case .address:
                        self.parent.suggestionsVM.selectNext()
                    case .semantic:
                        self.parent.semanticSearchVM.selectNext()
                    case .readingList:
                        self.parent.readingListVM.selectNext()
                    case .chat, .agent, .scraping:
                        break
                    }
                }
                switch parent.mode {
                case .address, .semantic, .readingList:
                    return true
                case .chat, .agent, .scraping:
                    return false
                }

            case .tab:
                parent.onTabPress()
                return true

            case .shiftTab:
                parent.onShiftTabPress()
                return true

            case .escape:
                NotificationCenter.default.post(name: .escapePressed, object: nil)
                return true

            case .deleteBackward:
                return false
            }
        }
    }
}
