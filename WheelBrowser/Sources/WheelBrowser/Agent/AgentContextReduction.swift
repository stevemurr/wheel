import Foundation

struct AgentTaskIntent: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case general
        case collectLinks
    }

    let kind: Kind
    let allowedHosts: [String]
    let pageLimit: Int?
    let requiresUniqueURLs: Bool

    var isLinkCollection: Bool {
        kind == .collectLinks
    }

    var snapshotRequest: SnapshotRequest {
        SnapshotRequest(
            maxInteractiveElements: isLinkCollection ? 12 : 18,
            includeHeadings: !isLinkCollection,
            includeContentSummary: !isLinkCollection,
            includePaginationControls: true,
            relevantHosts: allowedHosts,
            maxRelevantLinks: isLinkCollection ? 12 : 6
        )
    }

    var linkCollectionRequest: LinkCollectionRequest? {
        guard isLinkCollection else { return nil }
        return LinkCollectionRequest(
            allowedHosts: allowedHosts,
            includePaginationLinks: true,
            maxMatches: 250
        )
    }

    static func parse(task: String) -> AgentTaskIntent {
        let lowercased = task.lowercased()
        let domains = extractDomains(from: lowercased)
        let pageLimit = extractPageLimit(from: lowercased)
        let isLinkCollection = lowercased.contains("link")
            || lowercased.contains("url")
            || lowercased.contains("href")
            || lowercased.contains("arxiv")
        let requiresUniqueURLs = lowercased.contains("unique")
            || lowercased.contains("dedupe")
            || lowercased.contains("deduplic")

        return AgentTaskIntent(
            kind: isLinkCollection ? .collectLinks : .general,
            allowedHosts: domains,
            pageLimit: pageLimit,
            requiresUniqueURLs: requiresUniqueURLs || isLinkCollection
        )
    }

    private static func extractDomains(from task: String) -> [String] {
        let pattern = #"(?:https?://)?([a-z0-9-]+(?:\.[a-z0-9-]+)+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(task.startIndex..<task.endIndex, in: task)
        var hosts: [String] = []

        regex.enumerateMatches(in: task, options: [], range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges > 1,
                  let hostRange = Range(match.range(at: 1), in: task) else {
                return
            }

            let host = normalizeHost(task[hostRange])
            guard !host.isEmpty, !hosts.contains(host) else {
                return
            }
            hosts.append(host)
        }

        if task.contains("arxiv") && !hosts.contains("arxiv.org") {
            hosts.append("arxiv.org")
        }

        return hosts
    }

    private static func extractPageLimit(from task: String) -> Int? {
        let patterns = [
            #"(?:first|next|across|through|scan|browse)\s+(\d+)\s+pages?"#,
            #"(\d+)\s+pages?"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(task.startIndex..<task.endIndex, in: task)
            if let match = regex.firstMatch(in: task, options: [], range: range),
               match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: task),
               let value = Int(task[valueRange]) {
                return value
            }
        }

        return nil
    }

    private static func normalizeHost<S: StringProtocol>(_ host: S) -> String {
        let trimmed = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
    }
}

struct SnapshotRequest: Codable, Equatable, Sendable {
    let maxInteractiveElements: Int
    let includeHeadings: Bool
    let includeContentSummary: Bool
    let includePaginationControls: Bool
    let relevantHosts: [String]
    let maxRelevantLinks: Int
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

struct ReducedPageObservation: Sendable {
    let url: String
    let title: String
    let interactiveElements: [PageElement]
    let relevantLinks: [PageLink]
    let paginationLinks: [PageLink]
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
        paginationLinks: [PageLink] = [],
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

        self.paginationLinks = ReducedPageObservation.uniqueLinks(paginationLinks)
        self.totalPageLinkCount = max(totalPageLinkCount, uniqueRelevantLinks.count + self.paginationLinks.count)
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

        if !paginationLinks.isEmpty {
            lines.append("")
            lines.append("Pagination Controls:")
            for link in paginationLinks.prefix(5) {
                lines.append("  \(link.description)")
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
}

struct LinkCollectionRequest: Codable, Equatable, Sendable {
    let allowedHosts: [String]
    let includePaginationLinks: Bool
    let maxMatches: Int
}

struct LinkCollectionMatch: Codable, Equatable, Hashable, Sendable {
    let text: String
    let url: String
    let sourcePageURL: String

    var markdownLine: String {
        let label = text.isEmpty ? url : text
        return "- [\(label)](\(url))"
    }
}

struct LinkCollectionResult: Codable, Equatable, Sendable {
    let matches: [LinkCollectionMatch]
    let paginationLinks: [PageLink]
    let totalLinksScanned: Int
    let filteredOutCount: Int
}

struct AgentCollectionAccumulator: Equatable, Sendable {
    private(set) var collectedByURL: [String: LinkCollectionMatch] = [:]

    var totalUniqueCount: Int {
        collectedByURL.count
    }

    mutating func absorb(_ result: LinkCollectionResult) -> CollectionDelta {
        var added: [LinkCollectionMatch] = []
        var duplicates = 0

        for match in result.matches {
            if collectedByURL[match.url] == nil {
                collectedByURL[match.url] = match
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

    func summaryText(sampleLimit: Int = 5) -> String {
        guard !collectedByURL.isEmpty else {
            return "Collected links: none yet."
        }

        let sample = collectedByURL.values
            .sorted { $0.url < $1.url }
            .prefix(sampleLimit)
            .map(\.url)
            .joined(separator: "\n")

        return """
        Collected links: \(totalUniqueCount) unique URLs.
        Sample:
        \(sample)
        """
    }

    func artifacts(title: String) -> [ChatArtifact] {
        let sortedMatches = collectedByURL.values.sorted { $0.url < $1.url }
        let markdown = sortedMatches.map(\.markdownLine).joined(separator: "\n")
        let jsonData = try? JSONEncoder.prettyPrinted.encode(sortedMatches)
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
}

struct CollectionDelta: Equatable, Sendable {
    let added: [LinkCollectionMatch]
    let duplicateCount: Int
    let totalUniqueCount: Int

    var message: String {
        let addedCount = added.count
        let sample = added.prefix(3).map(\.url).joined(separator: ", ")
        if sample.isEmpty {
            return "\(addedCount) new matches, \(duplicateCount) duplicates, \(totalUniqueCount) total."
        }
        return "\(addedCount) new matches, \(duplicateCount) duplicates, \(totalUniqueCount) total. Sample: \(sample)"
    }
}

private extension URL {
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
