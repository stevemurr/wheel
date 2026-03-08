import Foundation

/// A structured source badge attached to chat messages.
/// These badges describe which context channels informed a request/response,
/// separate from the raw prompt text sent to the model.
public struct ChatContextBadge: Identifiable, Equatable, Hashable, Codable {
    public enum Kind: String, Codable, Hashable {
        case website
        case history
        case webSearch
        case readingList
        case domain
        case miniWindow
        case note
        case tool
        case toolResult
    }

    public let id: String
    public let kind: Kind
    public let title: String?
    public let detail: String?
    public let url: String?

    public init(
        id: String,
        kind: Kind,
        title: String? = nil,
        detail: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.url = url
    }

    static func website(id: String? = nil, title: String? = nil, url: String? = nil) -> Self {
        let resolvedTitle = preferredTitle(title, url: url)
        return ChatContextBadge(
            id: id ?? "website-\(url ?? resolvedTitle ?? UUID().uuidString)",
            kind: .website,
            title: resolvedTitle,
            url: url
        )
    }

    static func history(title: String? = nil, detail: String? = nil, url: String? = nil) -> Self {
        ChatContextBadge(
            id: url.map { "history-\($0)" } ?? "history-search",
            kind: .history,
            title: preferredTitle(title, url: url),
            detail: detail,
            url: url
        )
    }

    static func webSearch(resultsCount: Int? = nil) -> Self {
        ChatContextBadge(
            id: "web-search",
            kind: .webSearch,
            detail: countDetail(resultsCount)
        )
    }

    static func readingList(title: String? = nil, detail: String? = nil, url: String? = nil) -> Self {
        ChatContextBadge(
            id: url.map { "reading-list-\($0)" } ?? "reading-list-search",
            kind: .readingList,
            title: preferredTitle(title, url: url),
            detail: detail,
            url: url
        )
    }

    static func domain(_ domain: String, resultsCount: Int? = nil) -> Self {
        ChatContextBadge(
            id: "domain-\(domain)",
            kind: .domain,
            title: domain,
            detail: countDetail(resultsCount)
        )
    }

    static func miniWindow(title: String? = nil, url: String? = nil) -> Self {
        ChatContextBadge(
            id: "mini-window-\(url ?? title ?? UUID().uuidString)",
            kind: .miniWindow,
            title: preferredTitle(title, url: url),
            url: url
        )
    }

    static func note(id: UUID, title: String? = nil, detail: String? = nil) -> Self {
        ChatContextBadge(
            id: "note-\(id.uuidString)",
            kind: .note,
            title: preferredTitle(title, url: nil),
            detail: detail
        )
    }

    static func tool(name: String, detail: String? = nil) -> Self {
        ChatContextBadge(
            id: "tool-\(name)",
            kind: .tool,
            title: name,
            detail: detail
        )
    }

    static func toolResult(name: String, detail: String? = nil) -> Self {
        ChatContextBadge(
            id: "tool-result-\(name)",
            kind: .toolResult,
            title: name,
            detail: detail
        )
    }

    static func deduplicated(_ badges: [ChatContextBadge]) -> [ChatContextBadge] {
        var seen = Set<String>()
        var deduplicated: [ChatContextBadge] = []

        for badge in badges where seen.insert(badge.id).inserted {
            deduplicated.append(badge)
        }

        return deduplicated
    }

    private static func preferredTitle(_ title: String?, url: String?) -> String? {
        if let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedTitle.isEmpty,
           trimmedTitle.lowercased() != "untitled" {
            return trimmedTitle
        }

        if let url, !url.urlCleanDomain.isEmpty {
            return url.urlCleanDomain
        }

        return nil
    }

    private static func countDetail(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count == 1 ? "1 result" : "\(count) results"
    }
}
