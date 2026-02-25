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

    // MARK: - Clock Widget Formatters

    /// Time format for clock widget (e.g., "3:45")
    private static let clockTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    static func clockTime(from date: Date) -> String {
        clockTimeFormatter.string(from: date)
    }

    /// AM/PM format for clock widget
    private static let clockAmPmFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()

    static func clockAmPm(from date: Date) -> String {
        clockAmPmFormatter.string(from: date)
    }

    /// Full date format for clock widget (e.g., "Friday, January 5")
    private static let clockDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    static func clockFullDate(from date: Date) -> String {
        clockDateFormatter.string(from: date)
    }
}
