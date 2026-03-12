import Fabric
import Foundation

/// Represents a mention that provides context to the AI chat
enum Mention: Identifiable, Equatable, Hashable {
    case currentPage
    case pageSnapshot(id: UUID, title: String, url: String)
    case tab(id: UUID, title: String, url: String)
    case overlay(id: UUID, title: String, url: String) // Mini window
    case note(id: UUID, title: String, excerpt: String)
    case semanticResult(id: UUID, title: String, url: String)
    case history
    case web           // Search all indexed web content
    case readingList   // Search reading list items
    case domain(String) // Search within a specific domain

    var id: String {
        switch self {
        case .currentPage:
            return "current-page"
        case .pageSnapshot(let id, _, _):
            return "page-snapshot-\(id.uuidString)"
        case .tab(let id, _, _):
            return "tab-\(id.uuidString)"
        case .overlay(let id, _, _):
            return "overlay-\(id.uuidString)"
        case .note(let id, _, _):
            return "note-\(id.uuidString)"
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
        case .pageSnapshot:
            return "Snapshot"
        case .tab(_, let title, _):
            return title.isEmpty ? "Untitled" : String(title.prefix(30))
        case .overlay(_, let title, _):
            return title.isEmpty ? "Mini Window" : String(title.prefix(30))
        case .note(_, let title, _):
            return title.isEmpty ? "Untitled Note" : String(title.prefix(30))
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
        case .pageSnapshot:
            return "camera.viewfinder"
        case .tab:
            return "square.on.square"
        case .overlay:
            return "pip"
        case .note:
            return "note.text"
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
        case .pageSnapshot:
            return "Snapshot"
        case .tab:
            return "Tab"
        case .overlay:
            return "Mini"
        case .note:
            return "Note"
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
        case .pageSnapshot(_, _, let url):
            return url
        case .tab(_, _, let url):
            return url
        case .overlay(_, _, let url):
            return url
        case .note:
            return nil
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
        switch self {
        case .pageSnapshot(let id, _, _), .tab(let id, _, _):
            return id
        default:
            return nil
        }
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
        case .currentPage, .pageSnapshot, .tab, .overlay, .note, .semanticResult:
            return false
        }
    }

    /// Whether this mention can be automatically inserted as the default chat context.
    var isAutomaticDefaultContext: Bool {
        switch self {
        case .currentPage, .overlay:
            return true
        case .pageSnapshot, .tab, .note, .semanticResult, .history, .web, .readingList, .domain:
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

    var subtitleText: String? {
        switch self {
        case .pageSnapshot(_, let title, _):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .note(_, _, let excerpt):
            let trimmed = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }

    var fabricURI: FabricURI? {
        switch self {
        case .currentPage:
            return FabricURI(appID: WheelFabricAppID.browser, kind: "page", id: "current")
        case .pageSnapshot(let id, _, _):
            return FabricURI(appID: WheelFabricAppID.browser, kind: "page-snapshot", id: id.uuidString)
        case .tab(let id, _, _):
            return FabricURI(appID: WheelFabricAppID.browser, kind: "tab", id: id.uuidString)
        case .note(let id, _, _):
            return FabricURI(appID: WheelFabricAppID.notes, kind: "note", id: id.uuidString)
        case .overlay, .semanticResult, .history, .web, .readingList, .domain:
            return nil
        }
    }

    static func fabricBackedMention(
        from resource: FabricResourceDescriptor,
        currentTabID: UUID?
    ) -> Mention? {
        guard resource.capabilities.contains(.mention) else {
            return nil
        }

        switch (resource.uri.appID, resource.kind) {
        case (WheelFabricAppID.browser, "page"):
            return .currentPage

        case (WheelFabricAppID.browser, "page-snapshot"):
            guard let tabID = UUID(uuidString: resource.uri.id) else {
                return nil
            }

            return .pageSnapshot(
                id: tabID,
                title: resource.summary,
                url: resource.metadata["url"]?.stringValue ?? ""
            )

        case (WheelFabricAppID.browser, "tab"):
            guard let tabID = UUID(uuidString: resource.uri.id),
                  tabID != currentTabID else {
                return nil
            }

            return .tab(
                id: tabID,
                title: resource.title,
                url: resource.metadata["url"]?.stringValue ?? resource.summary
            )

        case (WheelFabricAppID.notes, "note"):
            guard let noteID = UUID(uuidString: resource.uri.id) else {
                return nil
            }

            return .note(
                id: noteID,
                title: resource.title,
                excerpt: resource.summary
            )

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
