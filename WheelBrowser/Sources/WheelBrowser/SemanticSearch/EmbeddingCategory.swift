import Foundation

/// Categories for embedding content to enable filtered semantic search.
///
/// Documents indexed with categories can be filtered during search using
/// the `@Web`, `@History`, and `@ReadingList` mentions in chat.
enum EmbeddingCategory: String, CaseIterable, Codable, Sendable {
    /// Browsing history - pages visited by the user
    case history

    /// Any web page content that has been indexed
    case web

    /// Pages saved to the reading list for later
    case readingList

    /// Default/uncategorized content
    case general

    /// Display name for UI
    var displayName: String {
        switch self {
        case .history: return "History"
        case .web: return "Web"
        case .readingList: return "Reading List"
        case .general: return "General"
        }
    }
}

extension Set where Element == EmbeddingCategory {
    /// Convert to array of raw value strings for DIndex API
    var categoryStrings: [String] {
        map { $0.rawValue }
    }
}
