import SwiftUI
import AppKit

/// Multi-line text editor for chat mode input.
/// Wraps NSTextView in NSScrollView for auto-resize up to ~6 lines.
/// Enter sends, Shift+Enter inserts newline.
struct OmniBarTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let keyboardHandler: any OmniBarKeyboardHandler
    var onSubmit: () -> Void
    var onAtTrigger: (String) -> Void
    var onAtDismiss: () -> Void
    /// Called when the editor's ideal height changes (1–6 lines).
    var onHeightChange: ((CGFloat) -> Void)?

    /// Maximum number of visible lines before scrolling internally
    private static let maxVisibleLines = 6
    static let lineHeight: CGFloat = 18
    static let verticalPadding: CGFloat = 8

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = ChatTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticTextCompletionEnabled = false
        OmniBarTextInputConfigurator.configure(textView)
        textView.delegate = context.coordinator
        textView.chatDelegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight()
        }

        OmniBarTextInputConfigurator.configure(textView)

        // Focus coordination (Rule 9: set focus before mode, Rule 11: no withAnimation on focus)
        if isFocused && !context.coordinator.isEditing {
            if let window = textView.window, window.firstResponder != textView {
                OmniBarWindowDiagnostics.shared.arm(reason: "chat-programmatic-focus")
                window.makeFirstResponder(textView)
            } else if textView.window == nil {
                // View not yet in window hierarchy (e.g. mode switch created a new NSView).
                // Retry after the current layout pass commits the view tree.
                let coordinator = context.coordinator
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak textView] in
                    guard coordinator.parent.isFocused,
                          !coordinator.isEditing,
                          let textView = textView,
                          let window = textView.window,
                          window.firstResponder != textView else { return }
                    OmniBarWindowDiagnostics.shared.arm(reason: "chat-delayed-programmatic-focus")
                    window.makeFirstResponder(textView)
                }
            }
        }

        // Show/hide placeholder
        context.coordinator.updatePlaceholder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Custom NSTextView Subclass

    /// Subclass to intercept key events before they become commands
    class ChatTextView: NSTextView {
        weak var chatDelegate: ChatTextViewDelegate?

        override func keyDown(with event: NSEvent) {
            // Enter without shift = submit
            if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
                if chatDelegate?.chatTextViewShouldSubmit(self) == true {
                    return // Swallowed
                }
            }
            super.keyDown(with: event)
        }

        override func doCommand(by selector: Selector) {
            if let command = KeyboardCommand.from(selector: selector) {
                if chatDelegate?.chatTextView(self, handleCommand: command) == true {
                    return // Swallowed
                }
            }
            super.doCommand(by: selector)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate, ChatTextViewDelegate {
        var parent: OmniBarTextEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isEditing = false
        private var placeholderLabel: NSTextField?

        init(_ parent: OmniBarTextEditor) {
            self.parent = parent
        }

        // MARK: - ChatTextViewDelegate

        func chatTextViewShouldSubmit(_ textView: ChatTextView) -> Bool {
            parent.onSubmit()
            return true
        }

        func chatTextView(_ textView: ChatTextView, handleCommand command: KeyboardCommand) -> Bool {
            // Don't intercept arrow keys in multi-line - let NSTextView handle them
            switch command {
            case .moveUp, .moveDown:
                return false
            default:
                return parent.keyboardHandler.handleKeyboardCommand(command, mode: .chat, text: parent.text)
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            OmniBarWindowDiagnostics.shared.arm(reason: "chat-user-focus")
            if let textView {
                OmniBarTextInputConfigurator.configure(textView)
            }
            DispatchQueue.main.async {
                // Wrap in withAnimation so pill expansion animates smoothly
                // alongside the panel open. Safe now that .animation() was
                // removed from omniBarContent (no overlapping contexts).
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
            guard let textView = textView else { return }
            let newText = textView.string
            parent.text = newText
            updateHeight()
            updatePlaceholder()

            // Check for @ trigger
            checkForAtTrigger(in: newText)
        }

        // MARK: - Height Management

        func updateHeight() {
            guard let textView = textView, let scrollView = scrollView else { return }

            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let contentHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? OmniBarTextEditor.lineHeight

            let maxHeight = CGFloat(OmniBarTextEditor.maxVisibleLines) * OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding
            let minHeight = OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding

            let targetHeight = min(max(contentHeight + OmniBarTextEditor.verticalPadding, minHeight), maxHeight)

            if abs(scrollView.frame.height - targetHeight) > 1 {
                scrollView.frame.size.height = targetHeight
                scrollView.needsLayout = true
            }

            scrollView.hasVerticalScroller = contentHeight + OmniBarTextEditor.verticalPadding > maxHeight

            // Notify SwiftUI so it can apply a matching .frame(height:)
            DispatchQueue.main.async {
                self.parent.onHeightChange?(targetHeight)
            }
        }

        // MARK: - Placeholder

        func updatePlaceholder() {
            guard let textView = textView else { return }

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
                        label.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.height)
                    ])
                    placeholderLabel = label
                }
                placeholderLabel?.stringValue = parent.placeholder
                placeholderLabel?.isHidden = false
            } else {
                placeholderLabel?.isHidden = true
            }
        }

        // MARK: - @ Trigger

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

/// Protocol for the chat text view to communicate with its coordinator
@MainActor
protocol ChatTextViewDelegate: AnyObject {
    func chatTextViewShouldSubmit(_ textView: OmniBarTextEditor.ChatTextView) -> Bool
    func chatTextView(_ textView: OmniBarTextEditor.ChatTextView, handleCommand: KeyboardCommand) -> Bool
}
