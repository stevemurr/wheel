import Foundation
import Combine

/// Tracks content blocking statistics across browser sessions
/// Note: WebKit Content Blockers don't provide per-request callbacks,
/// so this tracks estimated stats based on rule categories and page loads
@MainActor
class BlockingStats: ObservableObject {

    /// Shared singleton instance
    static let shared = BlockingStats()

    // MARK: - Published Properties

    /// Total estimated blocked items (persisted)
    @Published private(set) var totalBlocked: Int {
        didSet {
            UserDefaults.standard.set(totalBlocked, forKey: Keys.totalBlocked)
        }
    }

    /// Blocked items per category (persisted)
    @Published private(set) var blockedByCategory: [BlockingCategory: Int] {
        didSet {
            saveCategoryStats()
        }
    }

    /// Blocked items in current session
    @Published private(set) var sessionBlocked: Int = 0

    /// Pages loaded with blocking enabled
    @Published private(set) var pagesProtected: Int {
        didSet {
            UserDefaults.standard.set(pagesProtected, forKey: Keys.pagesProtected)
        }
    }

    /// Date of first recorded block
    @Published private(set) var trackingSince: Date? {
        didSet {
            if let date = trackingSince {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.trackingSince)
            }
        }
    }

    // MARK: - Private Properties

    private enum Keys {
        static let totalBlocked = "BlockingStats.totalBlocked"
        static let pagesProtected = "BlockingStats.pagesProtected"
        static let trackingSince = "BlockingStats.trackingSince"
        static let categoryPrefix = "BlockingStats.category."
    }

    // Estimated blocks per page load by category
    // These are conservative estimates based on typical ad/tracker density
    private let estimatedBlocksPerPage: [BlockingCategory: Int] = [
        .ads: 8,           // Typical page has 5-15 ad requests
        .trackers: 12,     // Analytics, pixels, etc.
        .socialWidgets: 3, // FB, Twitter, etc. widgets
        .annoyances: 2     // Cookie banners, chat widgets
    ]

    // MARK: - Initialization

    private init() {
        // Load persisted stats
        self.totalBlocked = UserDefaults.standard.integer(forKey: Keys.totalBlocked)
        self.pagesProtected = UserDefaults.standard.integer(forKey: Keys.pagesProtected)

        // Load tracking start date
        let timestamp = UserDefaults.standard.double(forKey: Keys.trackingSince)
        self.trackingSince = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil

        // Load category stats
        var categoryStats: [BlockingCategory: Int] = [:]
        for category in BlockingCategory.allCases {
            let count = UserDefaults.standard.integer(forKey: Keys.categoryPrefix + category.rawValue)
            categoryStats[category] = count
        }
        self.blockedByCategory = categoryStats
    }

    // MARK: - Public Methods

    /// Record a page load with content blocking enabled
    /// Estimates blocked items based on enabled categories
    func recordPageLoad(enabledCategories: Set<BlockingCategory>) {
        guard !enabledCategories.isEmpty else { return }

        // Set tracking start date if first record
        if trackingSince == nil {
            trackingSince = Date()
        }

        // Increment pages protected
        pagesProtected += 1

        // Estimate blocked items per category
        var pageBlocks = 0
        for category in enabledCategories {
            let estimate = estimatedBlocksPerPage[category] ?? 0
            blockedByCategory[category, default: 0] += estimate
            pageBlocks += estimate
        }

        totalBlocked += pageBlocks
        sessionBlocked += pageBlocks
    }

    /// Reset session statistics
    func resetSession() {
        sessionBlocked = 0
    }

    /// Reset all statistics
    func resetAllStats() {
        totalBlocked = 0
        sessionBlocked = 0
        pagesProtected = 0
        trackingSince = nil
        blockedByCategory = [:]

        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: Keys.totalBlocked)
        UserDefaults.standard.removeObject(forKey: Keys.pagesProtected)
        UserDefaults.standard.removeObject(forKey: Keys.trackingSince)
        for category in BlockingCategory.allCases {
            UserDefaults.standard.removeObject(forKey: Keys.categoryPrefix + category.rawValue)
        }
    }

    // MARK: - Computed Properties

    /// Formatted total blocked count (e.g., "1.2K", "3.5M")
    var formattedTotalBlocked: String {
        formatCount(totalBlocked)
    }

    /// Formatted session blocked count
    var formattedSessionBlocked: String {
        formatCount(sessionBlocked)
    }

    /// Days since tracking started
    var daysSinceStart: Int {
        guard let start = trackingSince else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
    }

    /// Average blocks per day
    var averageBlocksPerDay: Double {
        let days = max(daysSinceStart, 1)
        return Double(totalBlocked) / Double(days)
    }

    /// Formatted average blocks per day
    var formattedAveragePerDay: String {
        let avg = averageBlocksPerDay
        if avg >= 1000 {
            return String(format: "%.1fK", avg / 1000)
        }
        return String(format: "%.0f", avg)
    }

    // MARK: - Private Methods

    private func saveCategoryStats() {
        for (category, count) in blockedByCategory {
            UserDefaults.standard.set(count, forKey: Keys.categoryPrefix + category.rawValue)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Stats Summary

extension BlockingStats {

    /// Summary statistics for display
    struct Summary {
        let totalBlocked: String
        let sessionBlocked: String
        let pagesProtected: Int
        let topCategory: BlockingCategory?
        let topCategoryCount: String
        let daysSinceStart: Int
        let averagePerDay: String
    }

    /// Generate a summary of current stats
    var summary: Summary {
        let topCategory = blockedByCategory.max(by: { $0.value < $1.value })

        return Summary(
            totalBlocked: formattedTotalBlocked,
            sessionBlocked: formattedSessionBlocked,
            pagesProtected: pagesProtected,
            topCategory: topCategory?.key,
            topCategoryCount: formatCount(topCategory?.value ?? 0),
            daysSinceStart: daysSinceStart,
            averagePerDay: formattedAveragePerDay
        )
    }
}
