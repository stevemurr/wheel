import Foundation

/// Pre-action state capture for computing deltas after an action
typealias PreActionState = (url: String, title: String, elementCount: Int, captchaDetected: Bool)

/// Protocol for interacting with web pages, enabling dependency injection for testing
@MainActor
protocol BrowserBridge: AnyObject {
    func snapshot() async throws -> PageSnapshot
    func snapshot(request: SnapshotRequest) async throws -> ReducedPageObservation
    func click(elementId: Int, modifiers: ClickModifiers) async throws
    func type(elementId: Int, text: String) async throws
    func pressEnter() async throws
    func scroll(deltaX: Double, deltaY: Double) async throws
    func scrollToTop() async throws
    func scrollToBottom() async throws
    func waitForLoad(timeout: TimeInterval, stableThreshold: TimeInterval) async throws
    func readText(elementId: Int) async throws -> String
    func revalidateElement(elementId: Int, expectedTag: String?, expectedText: String?) async throws -> Int
    func getPageLinks() async throws -> String
    func collectLinks(_ request: LinkCollectionRequest) async throws -> LinkCollectionResult
    func capturePreActionState() async -> PreActionState
    func quickDelta(before: PreActionState) async -> ActionDelta
}

/// Convenience methods with default parameter values
extension BrowserBridge {
    func snapshot(request: SnapshotRequest) async throws -> ReducedPageObservation {
        let pageSnapshot = try await snapshot()
        let linkRequest = LinkCollectionRequest(
            allowedHosts: request.relevantHosts,
            includePaginationLinks: request.includePaginationControls,
            maxMatches: max(request.maxRelevantLinks * 3, request.maxRelevantLinks)
        )
        let linkResult = try await collectLinks(linkRequest)
        return ReducedPageObservation(
            snapshot: pageSnapshot,
            request: request,
            relevantLinks: linkResult.matches.map {
                PageLink(text: $0.text, url: $0.url, isPaginationControl: false)
            },
            paginationLinks: request.includePaginationControls ? linkResult.paginationLinks : [],
            totalPageLinkCount: linkResult.totalLinksScanned
        )
    }

    func click(elementId: Int) async throws {
        try await click(elementId: elementId, modifiers: .none)
    }

    func scroll(deltaY: Double) async throws {
        try await scroll(deltaX: 0, deltaY: deltaY)
    }

    func waitForLoad(timeout: TimeInterval = 5.0) async throws {
        try await waitForLoad(timeout: timeout, stableThreshold: 0.5)
    }

    func collectLinks(_ request: LinkCollectionRequest) async throws -> LinkCollectionResult {
        let currentURL = try await snapshot().url
        let rawLinks = try await getPageLinks()
        let lines = rawLinks
            .split(separator: "\n")
            .map(String.init)

        let parsedLinks = lines.compactMap { line -> PageLink? in
            guard let separatorRange = line.range(of: " -> ") else {
                return nil
            }
            let text = String(line[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = String(line[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else {
                return nil
            }
            let isPagination = PageLinkParser.isPaginationLabel(text)
            return PageLink(text: text == "(no text)" ? "" : text, url: url, isPaginationControl: isPagination)
        }

        let filteredMatches = parsedLinks.filter { link in
            guard !link.isPaginationControl else {
                return false
            }
            if request.allowedHosts.isEmpty {
                return true
            }
            return request.allowedHosts.contains(link.host)
        }

        let matches = filteredMatches.prefix(request.maxMatches).map {
            LinkCollectionMatch(text: $0.text, url: $0.url, sourcePageURL: currentURL)
        }
        let paginationLinks = request.includePaginationLinks
            ? parsedLinks.filter(\.isPaginationControl)
            : []

        return LinkCollectionResult(
            matches: Array(matches),
            paginationLinks: paginationLinks,
            totalLinksScanned: parsedLinks.count,
            filteredOutCount: max(0, parsedLinks.count - matches.count)
        )
    }
}

/// Protocol for providing a BrowserBridge for a given tab
@MainActor
protocol BrowserBridgeProvider: AnyObject {
    func bridge(for tabId: UUID) -> (any BrowserBridge)?
}

enum PageLinkParser {
    private static let paginationKeywords = [
        "next",
        "more",
        "older",
        "page ",
    ]

    static func isPaginationLabel(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return paginationKeywords.contains { normalized.contains($0) }
    }
}
