import SwiftUI

struct NavigationBar: View {
    @ObservedObject var tab: Tab
    @State private var urlText: String = ""
    @State private var isHovering: Bool = false
    @State private var findText: String = ""
    @FocusState private var isURLFieldFocused: Bool
    @FocusState private var isFindFieldFocused: Bool
    @StateObject private var suggestionsVM = SuggestionsViewModel()

    private var shouldExpand: Bool {
        isURLFieldFocused || isHovering
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()

                HStack(spacing: 12) {
                    // Navigation buttons - only show when expanded
                    if shouldExpand {
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
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }

                    // URL bar - pill shaped with suggestions overlay
                    URLBarWithSuggestions(
                        urlText: $urlText,
                        isURLFieldFocused: _isURLFieldFocused,
                        suggestionsVM: suggestionsVM,
                        shouldExpand: shouldExpand,
                        onSubmit: {
                            // Use selected suggestion if available
                            if let selected = suggestionsVM.selectedSuggestion {
                                urlText = selected.url
                            }
                            tab.load(urlText)
                            isURLFieldFocused = false
                            suggestionsVM.hide()
                        },
                        onClear: {
                            urlText = ""
                            suggestionsVM.clear()
                        },
                        onSuggestionSelect: { entry in
                            urlText = entry.url
                            tab.load(entry.url)
                            isURLFieldFocused = false
                            suggestionsVM.hide()
                        }
                    )
                    .zIndex(10)

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

            // Find bar
            if tab.isFindBarVisible {
                FindBar(tab: tab, findText: $findText, isFocused: _isFindFieldFocused)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldExpand)
        .animation(.easeInOut(duration: 0.2), value: isURLFieldFocused)
        .animation(.easeInOut(duration: 0.15), value: tab.isFindBarVisible)
        .animation(.easeInOut(duration: 0.15), value: tab.zoomLevel)
        .animation(.easeInOut(duration: 0.15), value: suggestionsVM.isVisible)
        .onChange(of: tab.url) { _, newURL in
            if !isURLFieldFocused {
                urlText = newURL?.absoluteString ?? ""
            }
        }
        .onChange(of: urlText) { _, newValue in
            if isURLFieldFocused {
                suggestionsVM.updateSuggestions(for: newValue)
            }
        }
        .onChange(of: isURLFieldFocused) { _, focused in
            if !focused {
                // Delay hiding to allow click on suggestion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suggestionsVM.hide()
                }
            } else if !urlText.isEmpty {
                suggestionsVM.updateSuggestions(for: urlText)
            }
        }
        .onAppear {
            urlText = tab.url?.absoluteString ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in
            isURLFieldFocused = true
            // Select all text when focusing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.keyWindow,
                   let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
                    fieldEditor.selectAll(nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in
            if isURLFieldFocused {
                if suggestionsVM.isVisible {
                    suggestionsVM.hide()
                } else {
                    isURLFieldFocused = false
                    // Restore URL to current page URL
                    urlText = tab.url?.absoluteString ?? ""
                }
            }
            if tab.isFindBarVisible {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tab.hideFindBar()
                }
                findText = ""
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
}

/// Custom TextField that handles keyboard events for suggestions navigation
struct AddressBarTextField: NSViewRepresentable {
    @Binding var text: String
    @FocusState var isURLFieldFocused: Bool
    @ObservedObject var suggestionsVM: SuggestionsViewModel
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = "Search or enter URL"
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
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressBarTextField

        init(_ parent: AddressBarTextField) {
            self.parent = parent
        }

        @objc func textFieldAction(_ sender: NSTextField) {
            parent.onSubmit()
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                // Up arrow - select previous suggestion
                parent.suggestionsVM.selectPrevious()
                updateTextFieldWithSelection(control as? NSTextField)
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                // Down arrow - select next suggestion
                parent.suggestionsVM.selectNext()
                updateTextFieldWithSelection(control as? NSTextField)
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape key - handled by notification
                return false
            }
            return false
        }

        @MainActor
        private func updateTextFieldWithSelection(_ textField: NSTextField?) {
            // The selection is shown visually in the dropdown
            // No need to update the text field here
        }
    }
}

// Reusable navigation button component
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

// URL bar with suggestions that appear above
struct URLBarWithSuggestions: View {
    @Binding var urlText: String
    @FocusState var isURLFieldFocused: Bool
    @ObservedObject var suggestionsVM: SuggestionsViewModel
    let shouldExpand: Bool
    let onSubmit: () -> Void
    let onClear: () -> Void
    let onSuggestionSelect: (HistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Suggestions dropdown - appears above the URL bar
            if suggestionsVM.isVisible && isURLFieldFocused {
                AddressBarSuggestions(viewModel: suggestionsVM, onSelect: onSuggestionSelect)
                    .frame(width: shouldExpand ? 480 : 300)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // URL bar - pill shaped
            HStack(spacing: 8) {
                Image(systemName: isURLFieldFocused ? "pencil" : "magnifyingglass")
                    .foregroundColor(isURLFieldFocused ? .accentColor : .secondary)
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))

                AddressBarTextField(
                    text: $urlText,
                    isURLFieldFocused: _isURLFieldFocused,
                    suggestionsVM: suggestionsVM,
                    onSubmit: onSubmit
                )

                // Clear button when focused and has text
                if isURLFieldFocused && !urlText.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: shouldExpand ? 400 : 280, maxWidth: shouldExpand ? 500 : 320)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: isURLFieldFocused ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.15),
                        radius: isURLFieldFocused ? 8 : 4,
                        x: 0,
                        y: 2
                    )
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        isURLFieldFocused ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.1),
                        lineWidth: isURLFieldFocused ? 2 : 1
                    )
            }
        }
    }
}

// Find bar component for in-page search
struct FindBar: View {
    @ObservedObject var tab: Tab
    @Binding var findText: String
    @FocusState var isFocused: Bool

    var body: some View {
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

            Spacer()

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
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.95)
        }
    }
}
