import Foundation

extension Date {
    /// Returns a human-readable relative time string (e.g., "now", "5m ago", "2h ago", "3d ago")
    func relativeTimeString() -> String {
        let interval = Date().timeIntervalSince(self)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            return Date.shortDateFormatter.string(from: self)
        }
    }

    /// Cached DateFormatter for short date formatting (avoids creating new formatter on every call)
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()

    /// Cached RelativeDateTimeFormatter for abbreviated relative time formatting
    static let abbreviatedRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Returns an abbreviated relative time string using system formatting (e.g., "2 hr. ago")
    func abbreviatedRelativeTimeString() -> String {
        return Date.abbreviatedRelativeFormatter.localizedString(for: self, relativeTo: Date())
    }
}
