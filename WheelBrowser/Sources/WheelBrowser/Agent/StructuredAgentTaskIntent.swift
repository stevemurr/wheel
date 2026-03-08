import Foundation
import FoundationModels

enum AgentTaskIntentExtractionPrompt {
    static let instructions = """
    You extract structured browser-automation intent from a user's task.

    Represent the user's requested outcome, not your own preferred implementation.
    Do not rely on regex-style phrasing rules. Infer intent semantically from the request.
    Do not omit requirements like summaries, ranking, filtering, or page limits.
    Do not omit requested output formats such as tables.
    If the task asks for a fixed number of final items, set outputLimit to that number.
    If the task asks for summaries/descriptions/blurbs for each selected item, set requiresPerItemSummaries to true.
    If the task asks for links/items from only the current page or front page, use collectionMode `page_links`.
    Use collectionMode `paginated_links` only when the task requires gathering linked items across source pages.
    If the task explicitly asks for a table or tabular output, set finalResponseFormat to `markdown_table`.
    Use targetHosts only when the user explicitly or strongly implicitly wants a host/domain filter.
    Use canonicalizationStrategy `arxiv` only when the task explicitly targets arXiv links/papers.

    Site knowledge:
    - If the user asks about Hacker News, use seedURL `https://news.ycombinator.com/news`, sourceHosts [`news.ycombinator.com`], collectionStrategy `hacker_news_story_links`, and sourcePageIdentityStrategy `hacker_news_news_pages`.
    - On Hacker News feed tasks, the source pages are `/news` pages, while outbound articles are linked destinations.

    Return only structured data matching the schema.
    """
}

@Generable(description: "Structured intent for a browser automation task.")
struct GeneratedAgentTaskIntent: Sendable {
    @Guide(description: "Optional seed URL where the task should begin.")
    let seedURL: String?

    @Guide(description: "Source hosts the agent should scan for pages to inspect.")
    let sourceHosts: [String]

    @Guide(description: "Target hosts to filter linked destinations to. Leave empty when no host filter is requested.")
    let targetHosts: [String]

    @Guide(description: "Maximum number of source pages to scan, if specified.")
    let pageLimit: Int?

    @Guide(description: "Maximum number of final items to return, if specified.")
    let outputLimit: Int?

    @Guide(description: "True when duplicate URLs should be removed.")
    let requiresUniqueURLs: Bool

    @Guide(description: "True when each final selected item needs its own summary or description.")
    let requiresPerItemSummaries: Bool

    @Guide(description: "One of: none, page_links, paginated_links.")
    let collectionMode: String

    @Guide(description: "One of: none, arxiv.")
    let canonicalizationStrategy: String

    @Guide(description: "One of: generic, hacker_news_story_links.")
    let collectionStrategy: String

    @Guide(description: "One of: generic_host_pages, hacker_news_news_pages.")
    let sourcePageIdentityStrategy: String

    @Guide(description: "One of: unspecified, markdown_list, markdown_table.")
    let finalResponseFormat: String

    init(
        seedURL: String?,
        sourceHosts: [String],
        targetHosts: [String],
        pageLimit: Int?,
        outputLimit: Int?,
        requiresUniqueURLs: Bool,
        requiresPerItemSummaries: Bool,
        collectionMode: String,
        canonicalizationStrategy: String,
        collectionStrategy: String,
        sourcePageIdentityStrategy: String,
        finalResponseFormat: String
    ) {
        self.seedURL = seedURL
        self.sourceHosts = sourceHosts
        self.targetHosts = targetHosts
        self.pageLimit = pageLimit
        self.outputLimit = outputLimit
        self.requiresUniqueURLs = requiresUniqueURLs
        self.requiresPerItemSummaries = requiresPerItemSummaries
        self.collectionMode = collectionMode
        self.canonicalizationStrategy = canonicalizationStrategy
        self.collectionStrategy = collectionStrategy
        self.sourcePageIdentityStrategy = sourcePageIdentityStrategy
        self.finalResponseFormat = finalResponseFormat
    }

    func toTaskIntent() throws -> AgentTaskIntent {
        let normalizedSourceHosts = sourceHosts.map(Self.normalizedHost).filter { !$0.isEmpty }
        let normalizedTargetHosts = targetHosts.map(Self.normalizedHost).filter { !$0.isEmpty }

        guard let resolvedCollectionMode = AgentCollectionMode(rawValue: normalizedCollectionMode) else {
            throw AgentError.invalidLLMResponse("Unknown collection mode: \(collectionMode)")
        }
        guard let resolvedCanonicalization = LinkCanonicalizationStrategy(rawValue: normalizedCanonicalizationStrategy) else {
            throw AgentError.invalidLLMResponse("Unknown canonicalization strategy: \(canonicalizationStrategy)")
        }
        guard let resolvedCollectionStrategy = LinkCollectionStrategy(rawValue: normalizedCollectionStrategy) else {
            throw AgentError.invalidLLMResponse("Unknown collection strategy: \(collectionStrategy)")
        }
        guard let resolvedSourcePageIdentityStrategy = SourcePageIdentityStrategy(rawValue: normalizedSourcePageIdentityStrategy) else {
            throw AgentError.invalidLLMResponse("Unknown source page identity strategy: \(sourcePageIdentityStrategy)")
        }
        guard let resolvedFinalResponseFormat = AgentFinalResponseFormat(rawValue: normalizedFinalResponseFormat) else {
            throw AgentError.invalidLLMResponse("Unknown final response format: \(finalResponseFormat)")
        }

        return AgentTaskIntent(
            seedURL: seedURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sourceHosts: unique(normalizedSourceHosts),
            targetHosts: unique(normalizedTargetHosts),
            pageLimit: positiveValue(pageLimit),
            outputLimit: positiveValue(outputLimit),
            requiresUniqueURLs: requiresUniqueURLs || resolvedCollectionMode == .paginatedLinks,
            requiresPerItemSummaries: requiresPerItemSummaries,
            collectionMode: resolvedCollectionMode,
            canonicalizationStrategy: resolvedCanonicalization,
            collectionStrategy: resolvedCollectionStrategy,
            sourcePageIdentityStrategy: resolvedSourcePageIdentityStrategy,
            finalResponseFormat: resolvedFinalResponseFormat
        )
    }

    private var normalizedCollectionMode: String {
        switch collectionMode.lowercased() {
        case "page_links", "pagelinks":
            return AgentCollectionMode.pageLinks.rawValue
        case "paginated_links", "paginatedlinks":
            return AgentCollectionMode.paginatedLinks.rawValue
        case "none":
            return AgentCollectionMode.none.rawValue
        default:
            return collectionMode.lowercased()
        }
    }

    private var normalizedCanonicalizationStrategy: String {
        canonicalizationStrategy.lowercased()
    }

    private var normalizedCollectionStrategy: String {
        switch collectionStrategy.lowercased() {
        case "hacker_news_story_links", "hackernewsstorylinks":
            return LinkCollectionStrategy.hackerNewsStoryLinks.rawValue
        case "generic":
            return LinkCollectionStrategy.generic.rawValue
        default:
            return collectionStrategy.lowercased()
        }
    }

    private var normalizedSourcePageIdentityStrategy: String {
        switch sourcePageIdentityStrategy.lowercased() {
        case "generic_host_pages", "generichostpages":
            return SourcePageIdentityStrategy.genericHostPages.rawValue
        case "hacker_news_news_pages", "hackernewsnewspages":
            return SourcePageIdentityStrategy.hackerNewsNewsPages.rawValue
        default:
            return sourcePageIdentityStrategy.lowercased()
        }
    }

    private var normalizedFinalResponseFormat: String {
        switch finalResponseFormat.lowercased() {
        case "markdown_list", "markdownlist", "list":
            return AgentFinalResponseFormat.markdownList.rawValue
        case "markdown_table", "markdowntable", "table":
            return AgentFinalResponseFormat.markdownTable.rawValue
        case "none", "unspecified":
            return AgentFinalResponseFormat.unspecified.rawValue
        default:
            return finalResponseFormat.lowercased()
        }
    }

    private func positiveValue(_ value: Int?) -> Int? {
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    private static func normalizedHost(_ host: String) -> String {
        host
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []
        for value in values where seen.insert(value).inserted {
            uniqueValues.append(value)
        }
        return uniqueValues
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
