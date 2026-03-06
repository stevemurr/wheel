import SwiftUI
import AppKit

private enum OmniBarSingleLineLayout {
    static let height: CGFloat = OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding

    static func verticalInset(for textView: NSTextView) -> CGFloat {
        let font = textView.font ?? NSFont.systemFont(ofSize: 13)
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? font.ascender - font.descender + font.leading
        return max(0, floor((height - lineHeight) / 2))
    }
}

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

// MARK: - Custom Single-Line Text View for OmniBar

struct OmniBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let mode: OmniBarMode
    let placeholder: String
    let keyboardHandler: any OmniBarKeyboardHandler
    var onSubmit: () -> Void
    var onAtTrigger: (String) -> Void
    var onAtDismiss: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CommandTextScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = CommandTextView()
        textView.commandDelegate = context.coordinator
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: OmniBarSingleLineLayout.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: OmniBarSingleLineLayout.height)
        textView.frame = NSRect(x: 0, y: 0, width: 0, height: OmniBarSingleLineLayout.height)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: OmniBarSingleLineLayout.height
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        OmniBarTextInputConfigurator.configure(textView)
        textView.textContainerInset = NSSize(width: 0, height: OmniBarSingleLineLayout.verticalInset(for: textView))

        scrollView.documentView = textView
        scrollView.frame.size.height = OmniBarSingleLineLayout.height
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        OmniBarTextInputConfigurator.configure(textView)
        textView.textContainerInset = NSSize(width: 0, height: OmniBarSingleLineLayout.verticalInset(for: textView))
        context.coordinator.updatePlaceholder()
        requestFocusIfNeeded(for: textView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func requestFocusIfNeeded(for textView: NSTextView, coordinator: Coordinator) {
        guard isFocused, !coordinator.isEditing else { return }

        guard let window = textView.window else {
            scheduleFocusRetry(for: textView, coordinator: coordinator, reason: "single-line-delayed-focus-no-window")
            return
        }

        guard window.firstResponder !== textView else { return }

        OmniBarWindowDiagnostics.shared.arm(reason: "single-line-programmatic-focus")
        if !window.makeFirstResponder(textView) {
            scheduleFocusRetry(for: textView, coordinator: coordinator, reason: "single-line-delayed-focus-retry")
        }
    }

    private func scheduleFocusRetry(for textView: NSTextView, coordinator: Coordinator, reason: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard self.isFocused, !coordinator.isEditing else { return }
            guard let window = textView.window, window.firstResponder !== textView else { return }

            OmniBarWindowDiagnostics.shared.arm(reason: reason)
            _ = window.makeFirstResponder(textView)
        }
    }

    final class CommandTextView: NSTextView {
        weak var commandDelegate: CommandTextViewDelegate?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, commandDelegate?.commandTextViewShouldSubmit(self) == true {
                return
            }
            super.keyDown(with: event)
        }

        override func doCommand(by selector: Selector) {
            if let command = KeyboardCommand.from(selector: selector),
               commandDelegate?.commandTextView(self, handleCommand: command) == true {
                return
            }
            super.doCommand(by: selector)
        }
    }

    final class CommandTextScrollView: NSScrollView {
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: OmniBarSingleLineLayout.height)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, CommandTextViewDelegate {
        var parent: OmniBarTextField
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isEditing = false
        private var placeholderLabel: NSTextField?

        init(_ parent: OmniBarTextField) {
            self.parent = parent
        }

        func commandTextViewShouldSubmit(_ textView: CommandTextView) -> Bool {
            parent.onSubmit()
            return true
        }

        func commandTextView(_ textView: CommandTextView, handleCommand command: KeyboardCommand) -> Bool {
            parent.keyboardHandler.handleKeyboardCommand(command, mode: parent.mode, text: parent.text)
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            OmniBarWindowDiagnostics.shared.arm(reason: "single-line-user-focus")
            if let textView {
                OmniBarTextInputConfigurator.configure(textView)
            }
            DispatchQueue.main.async {
                withAnimation(AppAnimation.panelSpring) {
                    self.parent.isFocused = true
                }
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            guard isEditing else { return }
            isEditing = false
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }

            let sanitized = sanitize(textView.string)
            if sanitized != textView.string {
                textView.string = sanitized
            }

            parent.text = sanitized

            if parent.mode == .chat {
                checkForAtTrigger(in: sanitized)
            }

            updatePlaceholder()
        }

        func updatePlaceholder() {
            guard let textView else { return }

            if textView.string.isEmpty {
                if placeholderLabel == nil {
                    let label = NSTextField(labelWithString: parent.placeholder)
                    label.font = NSFont.systemFont(ofSize: 13)
                    label.textColor = .placeholderTextColor
                    label.isEditable = false
                    label.isSelectable = false
                    label.isBordered = false
                    label.drawsBackground = false
                    label.translatesAutoresizingMaskIntoConstraints = false
                    textView.addSubview(label)
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.width),
                        label.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
                    ])
                    placeholderLabel = label
                }
                placeholderLabel?.stringValue = parent.placeholder
                placeholderLabel?.isHidden = false
            } else {
                placeholderLabel?.isHidden = true
            }
        }

        private func sanitize(_ rawText: String) -> String {
            rawText
                .components(separatedBy: .newlines)
                .joined(separator: " ")
        }

        private func checkForAtTrigger(in text: String) {
            if let atIndex = text.lastIndex(of: "@") {
                let queryStartIndex = text.index(after: atIndex)
                let query = String(text[queryStartIndex...])

                let isValidTrigger: Bool
                if atIndex == text.startIndex {
                    isValidTrigger = true
                } else {
                    let beforeAt = text.index(before: atIndex)
                    isValidTrigger = text[beforeAt].isWhitespace
                }

                if isValidTrigger && !query.contains(" ") {
                    parent.onAtTrigger(query)
                    return
                }
            }

            parent.onAtDismiss()
        }
    }
}

@MainActor
protocol CommandTextViewDelegate: AnyObject {
    func commandTextViewShouldSubmit(_ textView: OmniBarTextField.CommandTextView) -> Bool
    func commandTextView(_ textView: OmniBarTextField.CommandTextView, handleCommand command: KeyboardCommand) -> Bool
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
        case #selector(NSResponder.insertTabIgnoringFieldEditor(_:)):
            return .tab
        case #selector(NSResponder.insertBacktab(_:)):
            return .shiftTab
        case #selector(NSWindow.selectNextKeyView(_:)):
            return .tab
        case #selector(NSWindow.selectPreviousKeyView(_:)):
            return .shiftTab
        case #selector(NSResponder.deleteBackward(_:)):
            return .deleteBackward
        default:
            return nil
        }
    }
}
