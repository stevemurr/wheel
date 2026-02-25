import Foundation

/// Cached DateFormatter instances for performance
/// Creating DateFormatter is expensive - this provides reusable instances
enum DateFormatterCache {
    // MARK: - Relative Time

    /// Format relative time strings like "5 minutes ago"
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Get a relative time string from a date
    static func relativeString(from date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Time Formatters

    /// Short time format (e.g., "3:45 PM")
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func shortTime(from date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }

    // MARK: - Date Formatters

    /// Short date format (e.g., "12/25/23")
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    static func shortDate(from date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    // MARK: - Combined Formatters

    /// Short date and time (e.g., "12/25/23, 3:45 PM")
    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func shortDateTime(from date: Date) -> String {
        shortDateTimeFormatter.string(from: date)
    }

}
