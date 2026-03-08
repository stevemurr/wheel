import Foundation

enum AgentCollectionMode: String, Codable, Equatable, Sendable {
    case none
    case paginatedLinks
}

enum LinkCanonicalizationStrategy: String, Codable, Equatable, Sendable {
    case none
    case arxiv
}

enum LinkCollectionStrategy: String, Codable, Equatable, Sendable {
    case generic
    case hackerNewsStoryLinks
}

enum SourcePageIdentityStrategy: String, Codable, Equatable, Sendable {
    case genericHostPages
    case hackerNewsNewsPages
}

struct AgentTaskIntent: Equatable, Sendable {
    let seedURL: String?
    let sourceHosts: [String]
    let targetHosts: [String]
    let pageLimit: Int?
    let outputLimit: Int?
    let requiresUniqueURLs: Bool
    let requiresPerItemSummaries: Bool
    let collectionMode: AgentCollectionMode
    let canonicalizationStrategy: LinkCanonicalizationStrategy
    let collectionStrategy: LinkCollectionStrategy
    let sourcePageIdentityStrategy: SourcePageIdentityStrategy

    var isLinkCollection: Bool {
        collectionMode == .paginatedLinks
    }

    var snapshotRequest: SnapshotRequest {
        SnapshotRequest(
            maxInteractiveElements: isLinkCollection ? 12 : 18,
            includeHeadings: !isLinkCollection || requiresPerItemSummaries,
            includeContentSummary: !isLinkCollection || requiresPerItemSummaries,
            includePaginationControls: true,
            relevantHosts: targetHosts,
            maxRelevantLinks: isLinkCollection ? 12 : 6,
            canonicalizationStrategy: canonicalizationStrategy,
            collectionStrategy: collectionStrategy
        )
    }

    var linkCollectionRequest: LinkCollectionRequest? {
        guard isLinkCollection else { return nil }
        let maxMatches: Int
        switch collectionStrategy {
        case .generic:
            maxMatches = 250
        case .hackerNewsStoryLinks:
            if let outputLimit {
                maxMatches = max(outputLimit * 3, 30)
            } else {
                maxMatches = 60
            }
        }
        return LinkCollectionRequest(
            targetHosts: targetHosts,
            includePaginationLinks: true,
            maxMatches: maxMatches,
            canonicalizationStrategy: canonicalizationStrategy,
            collectionStrategy: collectionStrategy
        )
    }

    static let empty = AgentTaskIntent(
        seedURL: nil,
        sourceHosts: [],
        targetHosts: [],
        pageLimit: nil,
        outputLimit: nil,
        requiresUniqueURLs: true,
        requiresPerItemSummaries: false,
        collectionMode: .none,
        canonicalizationStrategy: .none,
        collectionStrategy: .generic,
        sourcePageIdentityStrategy: .genericHostPages
    )
}

struct SnapshotRequest: Codable, Equatable, Sendable {
    let maxInteractiveElements: Int
    let includeHeadings: Bool
    let includeContentSummary: Bool
    let includePaginationControls: Bool
    let relevantHosts: [String]
    let maxRelevantLinks: Int
    let canonicalizationStrategy: LinkCanonicalizationStrategy
    let collectionStrategy: LinkCollectionStrategy
}

struct PageLink: Codable, Equatable, Hashable, Sendable {
    let text: String
    let url: String
    let isPaginationControl: Bool

    var host: String {
        URL(string: url)?.normalizedAgentHost ?? ""
    }

    var description: String {
        if text.isEmpty {
            return url
        }
        return "\(text) -> \(url)"
    }
}

struct PaginationCandidate: Codable, Equatable, Hashable, Sendable {
    let text: String
    let url: String
    let identity: String

    init(text: String, url: String, identity: String? = nil) {
        self.text = text
        self.url = url
        self.identity = identity ?? Self.identity(for: url)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        url = try container.decode(String.self, forKey: .url)
        identity = try container.decodeIfPresent(String.self, forKey: .identity) ?? Self.identity(for: url)
    }

    var description: String {
        if text.isEmpty {
            return url
        }
        return "\(text) -> \(url)"
    }

    static func identity(for url: String) -> String {
        if var components = URLComponents(string: url) {
            components.fragment = nil
            return (components.string ?? url).lowercased()
        }

        return url.lowercased()
    }
}

struct ReducedPageObservation: Sendable {
    let url: String
    let title: String
    let interactiveElements: [PageElement]
    let relevantLinks: [PageLink]
    let paginationCandidates: [PaginationCandidate]
    let headings: [PageHeading]
    let contentSummary: String?
    let scrollPosition: PageSnapshot.ScrollPosition
    let viewportSize: PageSnapshot.ViewportSize
    let captchaDetected: Bool
    let captchaType: String?
    let omittedInteractiveElementCount: Int
    let omittedRelevantLinkCount: Int
    let totalRelevantLinkCount: Int
    let totalPageLinkCount: Int

    init(
        snapshot: PageSnapshot,
        request: SnapshotRequest,
        relevantLinks: [PageLink] = [],
        paginationCandidates: [PaginationCandidate] = [],
        totalPageLinkCount: Int = 0
    ) {
        self.url = snapshot.url
        self.title = snapshot.title
        self.scrollPosition = snapshot.scrollPosition
        self.viewportSize = snapshot.viewportSize
        self.captchaDetected = snapshot.captchaDetected
        self.captchaType = snapshot.captchaType
        self.headings = request.includeHeadings ? (snapshot.headings ?? []) : []
        self.contentSummary = request.includeContentSummary ? snapshot.contentSummary : nil

        let prioritizedElements = ReducedPageObservation.prioritizedElements(
            from: snapshot.elements,
            request: request
        )
        self.interactiveElements = prioritizedElements.selected
        self.omittedInteractiveElementCount = prioritizedElements.omittedCount

        let uniqueRelevantLinks = ReducedPageObservation.uniqueLinks(relevantLinks)
        self.totalRelevantLinkCount = uniqueRelevantLinks.count
        self.relevantLinks = Array(uniqueRelevantLinks.prefix(request.maxRelevantLinks))
        self.omittedRelevantLinkCount = max(0, uniqueRelevantLinks.count - self.relevantLinks.count)

        self.paginationCandidates = ReducedPageObservation.uniquePaginationCandidates(paginationCandidates)
        self.totalPageLinkCount = max(totalPageLinkCount, uniqueRelevantLinks.count + self.paginationCandidates.count)
    }

    var textRepresentation: String {
        var lines: [String] = [
            "URL: \(url)",
            "Title: \(title)",
            "Viewport: \(Int(viewportSize.width))x\(Int(viewportSize.height))",
            "Scroll: \(Int(scrollPosition.y))/\(Int(scrollPosition.maxY))",
        ]

        if captchaDetected {
            lines.append("")
            lines.append("CAPTCHA/CHALLENGE: \(captchaType ?? "unknown")")
        }

        if !headings.isEmpty {
            lines.append("")
            lines.append("Headings:")
            for heading in headings.prefix(6) {
                lines.append("  H\(heading.level): \(heading.text)")
            }
        }

        if let contentSummary, !contentSummary.isEmpty {
            lines.append("")
            lines.append("Content Summary:")
            lines.append(contentSummary)
        }

        lines.append("")
        lines.append("Relevant Links (\(relevantLinks.count)/\(totalRelevantLinkCount)):")
        if relevantLinks.isEmpty {
            lines.append("  none")
        } else {
            for link in relevantLinks {
                lines.append("  \(link.description)")
            }
        }
        if omittedRelevantLinkCount > 0 {
            lines.append("  ... \(omittedRelevantLinkCount) more matching links omitted")
        }

        if !paginationCandidates.isEmpty {
            lines.append("")
            lines.append("Pagination Controls:")
            for candidate in paginationCandidates.prefix(5) {
                lines.append("  \(candidate.description)")
            }
        }

        lines.append("")
        lines.append("Interactive Elements (\(interactiveElements.count)):")
        if interactiveElements.isEmpty {
            lines.append("  none")
        } else {
            for element in interactiveElements {
                lines.append("  \(element.description)")
            }
        }
        if omittedInteractiveElementCount > 0 {
            lines.append("  ... \(omittedInteractiveElementCount) more elements omitted")
        }

        return lines.joined(separator: "\n")
    }

    private static func prioritizedElements(
        from elements: [PageElement],
        request: SnapshotRequest
    ) -> (selected: [PageElement], omittedCount: Int) {
        let paginationKeywords = ["next", "more", "older", "page 2", "page 3"]
        let relevantHostSet = Set(request.relevantHosts)

        let scored = elements.map { element -> (PageElement, Int) in
            var score = 0

            if let href = element.href,
               let host = URL(string: href)?.normalizedAgentHost,
               relevantHostSet.contains(host) {
                score += 60
            }

            let label = [element.text, element.ariaLabel, element.placeholder]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            if paginationKeywords.contains(where: label.contains) {
                score += 40
            }

            switch element.tag {
            case "a":
                score += 15
            case "button":
                score += 10
            case "input", "textarea", "select":
                score += 20
            default:
                break
            }

            return (element, score)
        }

        let selected = scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                let lhsY = lhs.0.boundingBox?.y ?? .greatestFiniteMagnitude
                let rhsY = rhs.0.boundingBox?.y ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }
            .prefix(request.maxInteractiveElements)
            .map { $0.0 }

        return (selected, max(0, elements.count - selected.count))
    }

    private static func uniqueLinks(_ links: [PageLink]) -> [PageLink] {
        var seen = Set<String>()
        var unique: [PageLink] = []

        for link in links {
            guard seen.insert(link.url).inserted else {
                continue
            }
            unique.append(link)
        }

        return unique
    }

    private static func uniquePaginationCandidates(_ candidates: [PaginationCandidate]) -> [PaginationCandidate] {
        var seen = Set<String>()
        var unique: [PaginationCandidate] = []

        for candidate in candidates {
            guard seen.insert(candidate.identity).inserted else {
                continue
            }
            unique.append(candidate)
        }

        return unique
    }
}

struct LinkCollectionRequest: Codable, Equatable, Sendable {
    let targetHosts: [String]
    let includePaginationLinks: Bool
    let maxMatches: Int
    let canonicalizationStrategy: LinkCanonicalizationStrategy
    let collectionStrategy: LinkCollectionStrategy
}

struct LinkCollectionMatch: Codable, Equatable, Hashable, Sendable {
    let text: String
    let url: String
    let canonicalURL: String
    let canonicalID: String?
    let sourcePageURL: String
    let pageIndex: Int

    init(
        text: String,
        url: String,
        canonicalURL: String? = nil,
        canonicalID: String? = nil,
        sourcePageURL: String,
        pageIndex: Int = 0
    ) {
        self.text = text
        self.url = url
        self.canonicalURL = canonicalURL ?? url
        self.canonicalID = canonicalID
        self.sourcePageURL = sourcePageURL
        self.pageIndex = pageIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        url = try container.decode(String.self, forKey: .url)
        canonicalURL = try container.decodeIfPresent(String.self, forKey: .canonicalURL) ?? url
        canonicalID = try container.decodeIfPresent(String.self, forKey: .canonicalID)
        sourcePageURL = try container.decode(String.self, forKey: .sourcePageURL)
        pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0
    }

    var markdownLine: String {
        let label = text.isEmpty ? canonicalURL : text
        return "- [\(label)](\(canonicalURL))"
    }

    func withPageIndex(_ pageIndex: Int) -> LinkCollectionMatch {
        LinkCollectionMatch(
            text: text,
            url: url,
            canonicalURL: canonicalURL,
            canonicalID: canonicalID,
            sourcePageURL: sourcePageURL,
            pageIndex: pageIndex
        )
    }
}

struct LinkCollectionResult: Codable, Equatable, Sendable {
    let matches: [LinkCollectionMatch]
    let paginationCandidates: [PaginationCandidate]
    let totalLinksScanned: Int
    let filteredOutCount: Int
    let pageURL: String
    let pageHost: String

    func withPageIndex(_ pageIndex: Int) -> LinkCollectionResult {
        LinkCollectionResult(
            matches: matches.map { $0.withPageIndex(pageIndex) },
            paginationCandidates: paginationCandidates,
            totalLinksScanned: totalLinksScanned,
            filteredOutCount: filteredOutCount,
            pageURL: pageURL,
            pageHost: pageHost
        )
    }
}

struct AgentCollectionSummary: Codable, Equatable, Sendable {
    let pagesScanned: Int
    let pageLimit: Int?
    let sourceHosts: [String]
    let targetHosts: [String]
    let totalUniqueCount: Int
    let items: [LinkCollectionMatch]
}

struct AgentCrawlSession: Equatable, Sendable {
    let sourceHosts: [String]
    let targetHosts: [String]
    let pageLimit: Int?
    let sourcePageIdentityStrategy: SourcePageIdentityStrategy

    private(set) var pagesScanned: Int = 0
    private(set) var currentPageIndex: Int = 0
    private(set) var visitedPageURLs: Set<String> = []
    private(set) var visitedPaginationTargets: Set<String> = []
    private(set) var pageIndexByURL: [String: Int] = [:]
    private(set) var collectedPageURLs: Set<String> = []
    private(set) var lastPaginationCandidates: [PaginationCandidate] = []
    private(set) var paginationExhausted: Bool = false
    private(set) var hasMaterializedCollectionResult: Bool = false

    init(intent: AgentTaskIntent) {
        self.sourceHosts = intent.sourceHosts
        self.targetHosts = intent.targetHosts
        self.pageLimit = intent.pageLimit
        self.sourcePageIdentityStrategy = intent.sourcePageIdentityStrategy
    }

    var pageBudgetReached: Bool {
        guard let pageLimit else { return false }
        return pagesScanned >= pageLimit
    }

    var hasAvailablePaginationCandidate: Bool {
        !lastPaginationCandidates.isEmpty
    }

    mutating func observePage(url: String, paginationCandidates: [PaginationCandidate]) {
        let normalizedURL = normalizedPageURL(url)

        if isSourcePage(url: url), !normalizedURL.isEmpty {
            if let existingIndex = pageIndexByURL[normalizedURL] {
                currentPageIndex = existingIndex
            } else if let explicitPageIndex = resolvedPageIndex(for: url) {
                currentPageIndex = explicitPageIndex
                visitedPageURLs.insert(normalizedURL)
                pageIndexByURL[normalizedURL] = explicitPageIndex
                pagesScanned = max(pagesScanned, explicitPageIndex)
            } else {
                pagesScanned += 1
                currentPageIndex = pagesScanned
                visitedPageURLs.insert(normalizedURL)
                pageIndexByURL[normalizedURL] = currentPageIndex
            }
        }

        lastPaginationCandidates = paginationCandidates.filter { !visitedPaginationTargets.contains($0.identity) }
        paginationExhausted = lastPaginationCandidates.isEmpty
    }

    mutating func resolvePaginationCandidate(preferredURL: String?) -> PaginationCandidate? {
        if let preferredURL, !preferredURL.isEmpty {
            let identity = PaginationCandidate.identity(for: preferredURL)
            guard !visitedPaginationTargets.contains(identity) else {
                return nil
            }

            if let match = lastPaginationCandidates.first(where: { $0.identity == identity || $0.url == preferredURL }) {
                return match
            }

            return PaginationCandidate(text: "", url: preferredURL, identity: identity)
        }

        return lastPaginationCandidates.first
    }

    mutating func registerPaginationVisit(_ candidate: PaginationCandidate) -> Bool {
        let inserted = visitedPaginationTargets.insert(candidate.identity).inserted
        if inserted {
            lastPaginationCandidates.removeAll { $0.identity == candidate.identity }
        }
        paginationExhausted = lastPaginationCandidates.isEmpty
        return inserted
    }

    mutating func markCollectionMaterialized() {
        hasMaterializedCollectionResult = true
    }

    func shouldCollectPage(url: String) -> Bool {
        guard isSourcePage(url: url) else {
            return false
        }

        let normalizedURL = normalizedPageURL(url)
        guard !normalizedURL.isEmpty else {
            return false
        }

        return !collectedPageURLs.contains(normalizedURL)
    }

    mutating func markCollectedPage(url: String) {
        guard isSourcePage(url: url) else {
            return
        }

        let normalizedURL = normalizedPageURL(url)
        guard !normalizedURL.isEmpty else {
            return
        }

        collectedPageURLs.insert(normalizedURL)
        hasMaterializedCollectionResult = true
    }

    func isSourcePage(url: String) -> Bool {
        switch sourcePageIdentityStrategy {
        case .genericHostPages:
            guard !sourceHosts.isEmpty else {
                return true
            }
            return sourceHosts.contains(URL(string: url)?.normalizedAgentHost ?? "")
        case .hackerNewsNewsPages:
            guard let components = URLComponents(string: url) else {
                return false
            }
            return normalizedPageHost(components.host) == "news.ycombinator.com"
                && (components.path == "/news" || components.path == "/news/")
        }
    }

    func normalizedPageURL(_ url: String) -> String {
        if var components = URLComponents(string: url) {
            components.fragment = nil
            return components.string ?? url
        }

        return url
    }

    private func resolvedPageIndex(for url: String) -> Int? {
        switch sourcePageIdentityStrategy {
        case .genericHostPages:
            return nil
        case .hackerNewsNewsPages:
            guard let components = URLComponents(string: url),
                  normalizedPageHost(components.host) == "news.ycombinator.com",
                  components.path == "/news" || components.path == "/news/" else {
                return nil
            }

            let pageValue = components.queryItems?
                .first(where: { $0.name == "p" })?
                .value
                .flatMap(Int.init) ?? 1
            return max(1, pageValue)
        }
    }

    private func normalizedPageHost(_ host: String?) -> String {
        guard let host else {
            return ""
        }
        return host.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}

struct AgentCollectionAccumulator: Equatable, Sendable {
    private(set) var collectedByKey: [String: LinkCollectionMatch] = [:]

    var totalUniqueCount: Int {
        collectedByKey.count
    }

    var sortedMatches: [LinkCollectionMatch] {
        collectedByKey.values.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex {
                return lhs.pageIndex < rhs.pageIndex
            }
            return lhs.canonicalURL < rhs.canonicalURL
        }
    }

    mutating func absorb(_ result: LinkCollectionResult) -> CollectionDelta {
        var added: [LinkCollectionMatch] = []
        var duplicates = 0

        for match in result.matches {
            let key = dedupeKey(for: match)
            if collectedByKey[key] == nil {
                collectedByKey[key] = match
                added.append(match)
            } else {
                duplicates += 1
            }
        }

        return CollectionDelta(
            added: added,
            duplicateCount: duplicates,
            totalUniqueCount: totalUniqueCount
        )
    }

    func summaryText(sampleLimit: Int = 5, outputLimit: Int? = nil) -> String {
        guard !collectedByKey.isEmpty else {
            return "Collected links: none yet."
        }

        let selected = selectedMatches(limit: outputLimit)
        let sample = selected
            .prefix(sampleLimit)
            .map(\.canonicalURL)
            .joined(separator: "\n")
        let header: String
        if selected.count < totalUniqueCount {
            header = "Collected links: \(totalUniqueCount) unique URLs. Showing top \(selected.count) by source order."
        } else {
            header = "Collected links: \(totalUniqueCount) unique URLs."
        }

        return """
        \(header)
        Sample:
        \(sample)
        """
    }

    func selectedMatches(limit: Int? = nil) -> [LinkCollectionMatch] {
        let matches = sortedMatches
        guard let limit, limit > 0 else {
            return matches
        }
        return Array(matches.prefix(limit))
    }

    func artifacts(title: String, outputLimit: Int? = nil) -> [ChatArtifact] {
        let artifactMatches = selectedMatches(limit: outputLimit)
        let markdown = artifactMatches.isEmpty
            ? "No collected links."
            : artifactMatches.map(\.markdownLine).joined(separator: "\n")
        let jsonData = try? JSONEncoder.prettyPrinted.encode(artifactMatches)
        let jsonText = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return [
            ChatArtifact(
                title: "\(title) Links",
                language: "md",
                content: markdown,
                type: .markdown
            ),
            ChatArtifact(
                title: "\(title) Links JSON",
                language: "json",
                content: jsonText,
                type: .json
            ),
        ]
    }

    private func dedupeKey(for match: LinkCollectionMatch) -> String {
        if let canonicalID = match.canonicalID, !canonicalID.isEmpty {
            return "id:\(canonicalID)"
        }
        return "url:\(match.canonicalURL)"
    }
}

struct CollectionDelta: Equatable, Sendable {
    let added: [LinkCollectionMatch]
    let duplicateCount: Int
    let totalUniqueCount: Int

    var message: String {
        let addedCount = added.count
        let sample = added.prefix(3).map(\.canonicalURL).joined(separator: ", ")
        if sample.isEmpty {
            return "\(addedCount) new matches, \(duplicateCount) duplicates, \(totalUniqueCount) total."
        }
        return "\(addedCount) new matches, \(duplicateCount) duplicates, \(totalUniqueCount) total. Sample: \(sample)"
    }
}

enum LinkCollectionCanonicalizer {
    static func apply(
        to result: LinkCollectionResult,
        request: LinkCollectionRequest
    ) -> LinkCollectionResult {
        let matches = result.matches.map { apply(to: $0, strategy: request.canonicalizationStrategy) }
        return LinkCollectionResult(
            matches: matches,
            paginationCandidates: result.paginationCandidates,
            totalLinksScanned: result.totalLinksScanned,
            filteredOutCount: result.filteredOutCount,
            pageURL: result.pageURL,
            pageHost: result.pageHost
        )
    }

    private static func apply(
        to match: LinkCollectionMatch,
        strategy: LinkCanonicalizationStrategy
    ) -> LinkCollectionMatch {
        let canonicalized: (canonicalURL: String, canonicalID: String?)
        switch strategy {
        case .none:
            canonicalized = (match.url, nil)
        case .arxiv:
            canonicalized = canonicalizeArXiv(match.url)
        }

        return LinkCollectionMatch(
            text: match.text,
            url: match.url,
            canonicalURL: canonicalized.canonicalURL,
            canonicalID: canonicalized.canonicalID,
            sourcePageURL: match.sourcePageURL,
            pageIndex: match.pageIndex
        )
    }

    private static func canonicalizeArXiv(_ urlString: String) -> (canonicalURL: String, canonicalID: String?) {
        guard let components = URLComponents(string: urlString),
              normalizedHost(components.host) == "arxiv.org" else {
            return (urlString, nil)
        }

        let path = components.path
        let pattern = #"^/(?:abs/([A-Za-z0-9.\-]+)|pdf/([A-Za-z0-9.\-]+)\.pdf)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (urlString, nil)
        }

        let nsRange = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, options: [], range: nsRange),
              match.numberOfRanges > 2 else {
            return (urlString, nil)
        }

        let identifier: String?
        if let absRange = Range(match.range(at: 1), in: path) {
            identifier = String(path[absRange])
        } else if let pdfRange = Range(match.range(at: 2), in: path) {
            identifier = String(path[pdfRange])
        } else {
            identifier = nil
        }

        guard let identifier else {
            return (urlString, nil)
        }
        return ("https://arxiv.org/abs/\(identifier)", identifier)
    }

    private static func normalizedHost(_ host: String?) -> String {
        guard let host else { return "" }
        return host.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}

extension URL {
    var normalizedAgentHost: String? {
        host?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
