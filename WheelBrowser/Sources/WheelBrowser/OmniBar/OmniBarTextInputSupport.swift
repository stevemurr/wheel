import AppKit

@MainActor
enum OmniBarTextInputFocusCoordinator {
    static func requestFocusIfNeeded(
        isFocused: @escaping () -> Bool,
        isEditing: @escaping () -> Bool,
        for textView: NSTextView,
        immediateReason: String,
        delayedReason: String
    ) {
        guard isFocused(), !isEditing() else { return }

        guard let window = textView.window else {
            scheduleFocusRetry(
                isFocused: isFocused,
                isEditing: isEditing,
                for: textView,
                reason: delayedReason
            )
            return
        }

        guard window.firstResponder !== textView else { return }

        OmniBarWindowDiagnostics.shared.arm(reason: immediateReason)
        if !window.makeFirstResponder(textView) {
            scheduleFocusRetry(
                isFocused: isFocused,
                isEditing: isEditing,
                for: textView,
                reason: delayedReason
            )
        }
    }

    static func syncFocusLoss(
        isEditing: inout Bool,
        stillHasOmniBarInputFocus: @escaping () -> Bool,
        parentIsFocused: @escaping () -> Bool,
        onFocusLost: @escaping () -> Void
    ) {
        guard isEditing else { return }
        isEditing = false
        DispatchQueue.main.async {
            guard !stillHasOmniBarInputFocus() else { return }
            guard parentIsFocused() else { return }
            onFocusLost()
        }
    }

    private static func scheduleFocusRetry(
        isFocused: @escaping () -> Bool,
        isEditing: @escaping () -> Bool,
        for textView: NSTextView,
        reason: String
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard isFocused(), !isEditing() else { return }
            guard let window = textView.window, window.firstResponder !== textView else { return }
            OmniBarWindowDiagnostics.shared.arm(reason: reason)
            _ = window.makeFirstResponder(textView)
        }
    }
}
