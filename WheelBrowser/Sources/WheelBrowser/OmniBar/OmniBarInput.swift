import SwiftUI

// MARK: - Input Pill, Mentions, Mode Indicator, Action Button, TextField

extension OmniBar {
    // MARK: - Input Pill

    var inputPill: some View {
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
                readingListVM: readingListVM,
                omniState: omniState,
                placeholder: omniState.mode == .chat && !omniState.mentions.isEmpty ? "Ask about these pages..." : omniState.placeholder,
                onSubmit: handleSubmit,
                onTabPress: {
                    let wasChat = omniState.mode == .chat
                    omniState.nextMode()
                    // Reset mentions when entering chat mode
                    if !wasChat && omniState.mode == .chat {
                        omniState.resetMentions(includeCurrentPage: tab.url != nil)
                    }
                },
                onShiftTabPress: {
                    let wasChat = omniState.mode == .chat
                    omniState.previousMode()
                    // Reset mentions when entering chat mode
                    if !wasChat && omniState.mode == .chat {
                        omniState.resetMentions(includeCurrentPage: tab.url != nil)
                    }
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
                    isInputFocused ? omniState.modeColor.opacity(0.6) : Color.primary.opacity(0.1),
                    lineWidth: isInputFocused ? 2 : 1
                )
        }
    }

    // MARK: - Mention Chips

    var mentionChips: some View {
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

    var mentionDropdownPanel: some View {
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

    func handleAtTrigger(query: String) {
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

    func handleMentionSelection() {
        guard let suggestion = mentionSuggestionsVM.selectedSuggestion else { return }
        selectMentionSuggestion(suggestion)
    }

    func selectMentionSuggestion(_ suggestion: MentionSuggestion) {
        withAnimation(.easeInOut(duration: 0.15)) {
            omniState.addMention(suggestion.mention)
            omniState.dismissMentionDropdown()
        }
        mentionSuggestionsVM.clear()

        // Remove the @query from input text
        removeAtQueryFromInput()
    }

    func removeAtQueryFromInput() {
        // Find and remove @... pattern from input
        let text = omniState.inputText
        if let atIndex = text.lastIndex(of: "@") {
            omniState.inputText = String(text[..<atIndex])
        }
    }

    // MARK: - Mode Indicator

    var modeIndicator: some View {
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
    var actionButton: some View {
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

        case .readingList:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    readingListVM.loadSavedPages()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .scraping:
            EmptyView() // Scraping mode has no action button
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
                } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                    // If text is empty and there are mentions, remove the last one
                    if parent.text.isEmpty && !parent.omniState.mentions.isEmpty {
                        DispatchQueue.main.async {
                            Task { @MainActor in
                                // Remove the last mention
                                if let lastMention = self.parent.omniState.mentions.last {
                                    self.parent.omniState.removeMention(lastMention)
                                }
                            }
                        }
                        return true
                    }
                    return false // Let normal backspace behavior happen if text is not empty
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
                case .readingList:
                    parent.readingListVM.selectPrevious()
                    return true
                case .chat, .agent, .scraping:
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
                case .readingList:
                    parent.readingListVM.selectNext()
                    return true
                case .chat, .agent, .scraping:
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
