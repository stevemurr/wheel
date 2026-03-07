import Foundation

/// Represents a mention that provides context to the AI chat
enum Mention: Identifiable, Equatable, Hashable {
    case currentPage
    case tab(id: UUID, title: String, url: String)
    case overlay(id: UUID, title: String, url: String) // Mini window
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
        case .overlay(let id, _, _):
            return "overlay-\(id.uuidString)"
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
        case .overlay(_, let title, _):
            return title.isEmpty ? "Mini Window" : String(title.prefix(30))
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
        case .overlay:
            return "pip"
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
        case .overlay:
            return "Mini"
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
        case .overlay(_, _, let url):
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

    /// Returns the overlay ID if this is an overlay mention
    var overlayId: UUID? {
        if case .overlay(let id, _, _) = self {
            return id
        }
        return nil
    }

    /// Whether this mention represents a persistent search context that should survive across messages
    var isPersistent: Bool {
        switch self {
        case .web, .history, .readingList, .domain:
            return true
        case .currentPage, .tab, .overlay, .semanticResult:
            return false
        }
    }

    /// Whether this mention can be automatically inserted as the default chat context.
    var isAutomaticDefaultContext: Bool {
        switch self {
        case .currentPage, .overlay:
            return true
        case .tab, .semanticResult, .history, .web, .readingList, .domain:
            return false
        }
    }

    /// Returns the embedding category for this mention type, if applicable
    var embeddingCategory: EmbeddingCategory? {
        switch self {
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
