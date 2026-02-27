import AppKit

/// Utility for common pasteboard operations
enum PasteboardHelper {
    /// Copy a string to the system pasteboard
    /// - Parameter string: The string to copy
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Copy a URL to the system pasteboard
    /// - Parameter url: The URL to copy
    static func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}
