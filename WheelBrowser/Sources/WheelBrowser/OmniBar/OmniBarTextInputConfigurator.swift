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
}
