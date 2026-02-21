import Foundation

/// Represents a mention that provides context to the AI chat
enum Mention: Identifiable, Equatable, Hashable {
    case currentPage
    case tab(id: UUID, title: String, url: String)
    case semanticResult(id: UUID, title: String, url: String)
    case history
    case web           // Search all indexed web content
    case readingList   // Search reading list items
    case domain(String) // Search within a specific domain

    var id: String {
        switch self {
        case .currentPage:
            return "current-page"
        case .tab(let id, _, _):
            return "tab-\(id.uuidString)"
        case .semanticResult(let id, _, _):
            return "semantic-\(id.uuidString)"
        case .history:
            return "history-search"
        case .web:
            return "web-search"
        case .readingList:
            return "reading-list-search"
        case .domain(let domain):
            return "domain-\(domain)"
        }
    }

    var displayTitle: String {
        switch self {
        case .currentPage:
            return "Page"
        case .tab(_, let title, _):
            return title.isEmpty ? "Untitled" : String(title.prefix(30))
        case .semanticResult(_, let title, _):
            return title.isEmpty ? "Untitled" : String(title.prefix(30))
        case .history:
            return "History"
        case .web:
            return "Web"
        case .readingList:
            return "Reading List"
        case .domain(let domain):
            return domain
        }
    }

    var icon: String {
        switch self {
        case .currentPage:
            return "doc.text"
        case .tab:
            return "square.on.square"
        case .semanticResult:
            return "brain.head.profile"
        case .history:
            return "clock.arrow.circlepath"
        case .web:
            return "globe"
        case .readingList:
            return "bookmark"
        case .domain:
            return "link"
        }
    }

    var typeBadge: String {
        switch self {
        case .currentPage:
            return "Current"
        case .tab:
            return "Tab"
        case .semanticResult:
            return "History"
        case .history:
            return "Search"
        case .web:
            return "Search"
        case .readingList:
            return "Search"
        case .domain:
            return "Domain"
        }
    }

    var url: String? {
        switch self {
        case .currentPage:
            return nil
        case .tab(_, _, let url):
            return url
        case .semanticResult(_, _, let url):
            return url
        case .history, .web, .readingList:
            return nil
        case .domain:
            return nil
        }
    }

    /// Returns the tab ID if this is a tab mention
    var tabId: UUID? {
        if case .tab(let id, _, _) = self {
            return id
        }
        return nil
    }

    /// Returns the embedding category for this mention type, if applicable
    var embeddingCategory: EmbeddingCategory? {
        switch self {
        case .history:
            return .history
        case .web:
            return .web
        case .readingList:
            return .readingList
        default:
            return nil
        }
    }

    static func == (lhs: Mention, rhs: Mention) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A suggestion item in the mention dropdown
struct MentionSuggestion: Identifiable {
    let mention: Mention
    let score: Int

    var id: String { mention.id }
}
