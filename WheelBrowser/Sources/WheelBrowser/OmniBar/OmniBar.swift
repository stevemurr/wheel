import SwiftUI

/// The OmniBar - a unified input bar for both URL navigation and AI chat
struct OmniBar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var browserState: BrowserState
    @StateObject private var omniState = OmniBarState()
    @StateObject private var suggestionsVM = SuggestionsViewModel()

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

    var body: some View {
        VStack(spacing: 0) {
            // Suggestions panel - appears above OmniBar when in address mode (shows tabs + history)
            // Always in view hierarchy but hidden when not active to prevent first-render flash
            OmniPanel(
                title: "Go to",
                icon: "magnifyingglass",
                iconColor: .accentColor,
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
            // Always in view hierarchy but hidden when not active to prevent first-render flash
            OmniPanel(
                title: "AI Assistant",
                icon: "sparkles",
                iconColor: .purple,
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
        .onChange(of: tab.url) { _, newURL in
            if !isInputFocused && omniState.mode == .address {
                omniState.inputText = newURL?.absoluteString ?? ""
            }
        }
        .onChange(of: omniState.inputText) { _, newValue in
            if isInputFocused && omniState.mode == .address {
                if newValue.isEmpty {
                    suggestionsVM.loadRecentHistory()
                } else {
                    suggestionsVM.updateSuggestions(for: newValue)
                }
            }
        }
        .onChange(of: isInputFocused) { _, focused in
            omniState.isFocused = focused
            if !focused {
                // Delay hiding to allow click on suggestion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    suggestionsVM.hide()
                    if omniState.mode == .address {
                        omniState.dismissHistoryPanel()
                    }
                }
            } else if omniState.mode == .address {
                // Show history panel when focusing address bar
                omniState.openHistoryPanel()
                if omniState.inputText.isEmpty {
                    suggestionsVM.loadRecentHistory()
                } else {
                    suggestionsVM.updateSuggestions(for: omniState.inputText)
                }
            }
        }
        .onChange(of: omniState.mode) { _, newMode in
            // Handle panel visibility based on mode
            if newMode == .chat {
                suggestionsVM.hide()
                omniState.dismissHistoryPanel()
                // Show chat panel if there are messages
                if !agentManager.messages.isEmpty {
                    omniState.openChatPanel()
                }
            } else if newMode == .address {
                omniState.dismissChatPanel()
                // Show history panel if focused
                if isInputFocused {
                    omniState.openHistoryPanel()
                }
            }
        }
        .onAppear {
            omniState.inputText = tab.url?.absoluteString ?? ""
            // Connect suggestionsVM to browserState for tab searching
            suggestionsVM.browserState = browserState
            Task {
                if !agentManager.isReady && !agentManager.isLoading {
                    await agentManager.initialize()
                }
            }
            // Enable animations after the view has appeared to prevent first-render flash
            // Using a slight delay ensures the view hierarchy is fully established
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in
            omniState.setMode(.address)
            isInputFocused = true
            // Select all text when focusing
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
            // Show chat panel if there are messages
            if !agentManager.messages.isEmpty {
                omniState.openChatPanel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in
            omniState.setMode(.chat)
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in
            if tab.isFindBarVisible {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tab.hideFindBar()
                }
                findText = ""
            } else if omniState.showHistoryPanel {
                // Dismiss history panel if open
                omniState.dismissHistoryPanel()
                isInputFocused = false
                // Restore URL to current page URL
                omniState.inputText = tab.url?.absoluteString ?? ""
            } else if omniState.showChatPanel {
                // Dismiss chat panel if open
                omniState.dismissChatPanel()
                isInputFocused = false
            } else if isInputFocused {
                isInputFocused = false
                // Restore URL to current page URL in address mode
                if omniState.mode == .address {
                    omniState.inputText = tab.url?.absoluteString ?? ""
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
            // Subtle gradient background
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

            // Input field
            OmniBarTextField(
                text: $omniState.inputText,
                isFocused: $isInputFocused,
                mode: omniState.mode,
                suggestionsVM: suggestionsVM,
                placeholder: omniState.placeholder,
                onSubmit: handleSubmit,
                onTabPress: {
                    omniState.nextMode()
                },
                onShiftTabPress: {
                    omniState.previousMode()
                }
            )

            // Action button (clear in address mode, send in chat mode)
            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: shouldExpand ? 400 : 280, maxWidth: shouldExpand ? 500 : 320)
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

    // MARK: - Mode Indicator

    private var modeIndicator: some View {
        Button(action: { omniState.nextMode() }) {
            Image(systemName: omniState.modeIcon)
                .foregroundColor(isInputFocused ? omniState.modeColor : .secondary)
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help("Press Tab to switch modes")
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch omniState.mode {
        case .address:
            // Clear button when focused and has text
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
            // Send button
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
        }
    }

    // MARK: - Actions

    private func handleSubmit() {
        switch omniState.mode {
        case .address:
            submitAddress()
        case .chat:
            submitChat()
        }
    }

    private func submitAddress() {
        // Use selected suggestion if available
        if let selected = suggestionsVM.selectedSuggestion {
            handleSuggestionSelection(selected)
            return
        }
        tab.load(omniState.inputText)
        isInputFocused = false
        suggestionsVM.hide()
        omniState.dismissHistoryPanel()
    }

    /// Handle selection of a suggestion (either open tab or history entry)
    private func handleSuggestionSelection(_ suggestion: Suggestion) {
        switch suggestion {
        case .openTab(let tab, _):
            // Switch to the existing tab instead of loading the URL
            browserState.selectTab(tab.id)
            isInputFocused = false
            omniState.dismissHistoryPanel()
            suggestionsVM.hide()
            // Update the input text to show the selected tab's URL
            omniState.inputText = tab.url?.absoluteString ?? ""

        case .history(let entry, _):
            // Load the history entry URL in the current tab
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

        omniState.inputText = ""
        isSending = true

        // Show chat panel when sending a message
        omniState.openChatPanel()

        Task {
            let pageContext = await contentExtractor.extractContent(from: tab)
            await agentManager.sendMessage(content, pageContext: pageContext)
            isSending = false
        }
    }
}

// MARK: - Custom TextField for OmniBar

/// Custom TextField that handles keyboard events for both address and chat modes
struct OmniBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let mode: OmniBarMode
    @ObservedObject var suggestionsVM: SuggestionsViewModel
    let placeholder: String
    var onSubmit: () -> Void
    var onTabPress: () -> Void
    var onShiftTabPress: () -> Void

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
        // Update coordinator's parent reference so closures are fresh
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder

        // Handle focus changes from SwiftUI side
        if isFocused && nsView.window != nil && nsView.window?.firstResponder != nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OmniBarTextField
        /// Track if we've received a begin editing notification without a corresponding end
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
            // Guard against spurious end editing notifications that can occur
            // before we've actually begun editing (AppKit field editor setup quirk)
            guard isEditing else { return }
            isEditing = false

            // Verify we're actually losing focus by checking the first responder
            // after a brief delay to allow AppKit to settle
            if let textField = obj.object as? NSTextField {
                DispatchQueue.main.async {
                    // Only set isFocused to false if the text field is truly no longer the first responder
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
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter key - submit
                parent.onSubmit()
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                // Up arrow - select previous suggestion (address mode only)
                if parent.mode == .address {
                    parent.suggestionsVM.selectPrevious()
                    return true
                }
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                // Down arrow - select next suggestion (address mode only)
                if parent.mode == .address {
                    parent.suggestionsVM.selectNext()
                    return true
                }
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                // Tab key - switch mode
                parent.onTabPress()
                return true
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                // Shift+Tab - switch mode (backwards)
                parent.onShiftTabPress()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape key - post notification to dismiss overlay
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

/// Find bar component for in-page search (used by OmniBar)
struct OmniBarFindBar: View {
    @ObservedObject var tab: Tab
    @Binding var findText: String
    @FocusState var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                // Find input field
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

                // Navigation buttons
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

                // Close button
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
