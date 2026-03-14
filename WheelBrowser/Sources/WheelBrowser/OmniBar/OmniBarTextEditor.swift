import SwiftUI
import AppKit

/// Multi-line text editor for chat mode input.
/// Wraps NSTextView in NSScrollView for auto-resize up to ~6 lines.
/// Enter sends, Shift+Enter inserts newline.
struct OmniBarTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let moduleID: OmniBarModuleID
    let placeholder: String
    let supportsMentions: Bool
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

        // Avoid re-requesting first responder from inside an active edit session.
        // That creates a SwiftUI <-> AppKit focus feedback loop during panel/layout updates.
        OmniBarTextInputFocusCoordinator.requestFocusIfNeeded(
            isFocused: { self.isFocused },
            isEditing: { context.coordinator.isEditing },
            for: textView,
            immediateReason: "chat-programmatic-focus",
            delayedReason: "chat-delayed-programmatic-focus"
        )

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

        override func becomeFirstResponder() -> Bool {
            let didBecome = super.becomeFirstResponder()
            if didBecome {
                chatDelegate?.chatTextViewDidBecomeFirstResponder(self)
            }
            return didBecome
        }

        override func resignFirstResponder() -> Bool {
            let didResign = super.resignFirstResponder()
            if didResign {
                chatDelegate?.chatTextViewDidResignFirstResponder(self)
            }
            return didResign
        }

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

        func chatTextViewDidBecomeFirstResponder(_ textView: ChatTextView) {
            isEditing = true
            DispatchQueue.main.async {
                guard !self.parent.isFocused else { return }
                self.parent.isFocused = true
            }
        }

        func chatTextViewDidResignFirstResponder(_ textView: ChatTextView) {
            syncFocusLoss()
        }

        private func syncFocusLoss() {
            OmniBarTextInputFocusCoordinator.syncFocusLoss(
                isEditing: &isEditing,
                stillHasOmniBarInputFocus: { self.omniBarInputHasFirstResponder() },
                parentIsFocused: { self.parent.isFocused },
                onFocusLost: { self.parent.isFocused = false }
            )
        }

        func chatTextViewShouldSubmit(_ textView: ChatTextView) -> Bool {
            if parent.keyboardHandler.handleKeyboardCommand(.submit, moduleID: parent.moduleID, text: parent.text) {
                return true
            }
            parent.onSubmit()
            return true
        }

        func chatTextView(_ textView: ChatTextView, handleCommand command: KeyboardCommand) -> Bool {
            switch command {
            case .moveUp, .moveDown:
                // Let the chat module claim arrow keys for mention dropdown navigation,
                // but preserve native caret movement when there is no dropdown to handle.
                return parent.keyboardHandler.handleKeyboardCommand(command, moduleID: parent.moduleID, text: parent.text)
            default:
                return parent.keyboardHandler.handleKeyboardCommand(command, moduleID: parent.moduleID, text: parent.text)
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidBeginEditing(_ notification: Notification) {
            OmniBarWindowDiagnostics.shared.arm(reason: "chat-user-focus")
            if let textView {
                OmniBarTextInputConfigurator.configure(textView)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            syncFocusLoss()
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
                    let label = OmniBarTextInputConfigurator.makePlaceholderLabel(
                        text: parent.placeholder,
                        font: NSFont.systemFont(ofSize: 13)
                    )
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
            guard parent.supportsMentions else {
                parent.onAtDismiss()
                return
            }

            if let query = OmniBarMentionTriggerParser.query(in: text) {
                parent.onAtTrigger(query)
                return
            }
            parent.onAtDismiss()
        }

        private func omniBarInputHasFirstResponder() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            return responder is OmniBarTextEditor.ChatTextView
                || responder is OmniBarTextField.CommandTextView
        }
    }
}

/// Protocol for the chat text view to communicate with its coordinator
@MainActor
protocol ChatTextViewDelegate: AnyObject {
    func chatTextViewDidBecomeFirstResponder(_ textView: OmniBarTextEditor.ChatTextView)
    func chatTextViewDidResignFirstResponder(_ textView: OmniBarTextEditor.ChatTextView)
    func chatTextViewShouldSubmit(_ textView: OmniBarTextEditor.ChatTextView) -> Bool
    func chatTextView(_ textView: OmniBarTextEditor.ChatTextView, handleCommand: KeyboardCommand) -> Bool
}
