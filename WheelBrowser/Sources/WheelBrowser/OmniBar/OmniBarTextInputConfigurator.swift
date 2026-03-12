import AppKit

enum OmniBarTextInputConfigurator {
    static func configure(_ textField: NSTextField) {
        textField.isAutomaticTextCompletionEnabled = false
        textField.contentType = nil
    }

    /// Treat OmniBar inputs as plain command fields, not rich writing surfaces.
    /// This avoids first-focus initialization of macOS text services that can
    /// briefly flash their own auxiliary window.
    static func configure(_ textView: NSTextView) {
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.contentType = nil
    }

    static func makePlaceholderLabel(text: String, font: NSFont) -> NSTextField {
        let label = PassthroughPlaceholderLabel()
        label.stringValue = text
        label.font = font
        label.textColor = .placeholderTextColor
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

private final class PassthroughPlaceholderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
