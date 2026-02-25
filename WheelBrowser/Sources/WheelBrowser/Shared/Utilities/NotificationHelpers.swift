import Foundation

/// Helper functions for common notification patterns
enum NotificationHelpers {
    /// Posts a notification to open a URL in the active tab
    /// - Parameter url: The URL to open
    static func postOpenURL(_ url: URL) {
        NotificationCenter.default.post(name: .openURL, object: url)
    }

    /// Posts a notification to open a URL from a string
    /// - Parameter urlString: The URL string to open
    /// - Returns: True if the URL was valid and notification was posted
    @discardableResult
    static func postOpenURL(string urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        postOpenURL(url)
        return true
    }
}

// MARK: - URL Extension for Convenience

extension URL {
    /// Posts a notification to open this URL in the active tab
    func openInActiveTab() {
        NotificationHelpers.postOpenURL(self)
    }
}
