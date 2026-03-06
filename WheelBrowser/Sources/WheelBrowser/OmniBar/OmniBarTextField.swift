import SwiftUI

/// Protocol for handling keyboard commands from the OmniBar text field.
/// The parent view provides the implementation, absorbing mode-specific logic
/// that previously required passing multiple ViewModels as parameters.
@MainActor
protocol OmniBarKeyboardHandler {
    /// Handle a keyboard command in the current mode.
    /// - Parameters:
    ///   - command: The keyboard command to handle
    ///   - mode: The current OmniBar mode
    ///   - text: The current text in the field
    /// - Returns: `true` if the command was handled (swallow the event), `false` to let AppKit handle it
    func handleKeyboardCommand(_ command: KeyboardCommand, mode: OmniBarMode, text: String) -> Bool
}

// MARK: - Custom TextField for OmniBar

struct OmniBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let mode: OmniBarMode
    let placeholder: String
    let keyboardHandler: any OmniBarKeyboardHandler
    var onSubmit: () -> Void
    var onAtTrigger: (String) -> Void
    var onAtDismiss: () -> Void

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
                // Wrap in withAnimation so pill expansion (width, border, shadow)
                // animates smoothly alongside the panel open from setVisiblePanel().
                // This was previously forbidden because it overlapped with the
                // .animation() modifier on omniBarContent — but that modifier has
                // been removed, so this is now the sole animation driver for focus gain.
                withAnimation(AppAnimation.panelSpring) {
                    self.parent.isFocused = true
                }
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
                    parent.onAtTrigger(query)
                    return
                }
            }

            // No valid @ trigger - dismiss dropdown if open
            parent.onAtDismiss()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let command = KeyboardCommand.from(selector: commandSelector) else {
                return false
            }

            return parent.keyboardHandler.handleKeyboardCommand(command, mode: parent.mode, text: parent.text)
        }
    }
}

// MARK: - Keyboard Command

/// Typed representation of NSResponder keyboard selectors used in the OmniBar.
enum KeyboardCommand {
    case moveUp
    case moveDown
    case submit
    case escape
    case tab
    case shiftTab
    case deleteBackward

    /// Converts an NSResponder selector to a typed `KeyboardCommand`, if recognized.
    static func from(selector: Selector) -> KeyboardCommand? {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            return .moveUp
        case #selector(NSResponder.moveDown(_:)):
            return .moveDown
        case #selector(NSResponder.insertNewline(_:)):
            return .submit
        case #selector(NSResponder.cancelOperation(_:)):
            return .escape
        case #selector(NSResponder.insertTab(_:)):
            return .tab
        case #selector(NSResponder.insertBacktab(_:)):
            return .shiftTab
        case #selector(NSResponder.deleteBackward(_:)):
            return .deleteBackward
        default:
            return nil
        }
    }
}
