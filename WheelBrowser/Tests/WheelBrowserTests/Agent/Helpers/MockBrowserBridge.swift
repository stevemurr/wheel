import Foundation
@testable import WheelBrowser

/// Mock browser bridge that simulates page interactions for deterministic unit testing.
///
/// Configure with snapshots to return on each `snapshot()` call, and inspect
/// recorded actions to verify the agent took the expected steps.
@MainActor
final class MockBrowserBridge: BrowserBridge {
    /// Snapshots returned in order on each `snapshot()` call. Cycles the last one if exhausted.
    private var snapshots: [PageSnapshot]
    private var snapshotIndex = 0

    /// All actions recorded during the test
    private(set) var recordedActions: [RecordedAction] = []

    /// Current simulated URL (updated by navigate actions)
    var currentURL: String
    var currentTitle: String
    var queuedCollectionResults: [LinkCollectionResult]

    enum RecordedAction: Equatable {
        case click(elementId: Int, modifiers: ClickModifiers)
        case type(elementId: Int, text: String)
        case pressEnter
        case scroll(deltaX: Double, deltaY: Double)
        case scrollToTop
        case scrollToBottom
        case readText(elementId: Int)
        case waitForLoad(timeout: TimeInterval)
        case revalidateElement(elementId: Int)
    }

    init(
        snapshots: [PageSnapshot],
        initialURL: String = "https://example.com",
        initialTitle: String = "Example",
        queuedCollectionResults: [LinkCollectionResult] = []
    ) {
        self.snapshots = snapshots
        self.currentURL = initialURL
        self.currentTitle = initialTitle
        self.queuedCollectionResults = queuedCollectionResults
    }

    func snapshot() async throws -> PageSnapshot {
        guard !snapshots.isEmpty else {
            return PageSnapshotFactory.empty()
        }
        let snap = snapshots[min(snapshotIndex, snapshots.count - 1)]
        currentURL = snap.url
        currentTitle = snap.title
        snapshotIndex += 1
        return snap
    }

    func snapshot(request: SnapshotRequest) async throws -> ReducedPageObservation {
        let pageSnapshot = try await snapshot()
        let links = pageSnapshot.elements.compactMap { element -> PageLink? in
            guard let href = element.href else {
                return nil
            }

            let text = element.text ?? element.ariaLabel ?? element.placeholder ?? ""
            return PageLink(
                text: text,
                url: href,
                isPaginationControl: PageLinkParser.isPaginationLabel(text)
            )
        }

        let requestForLinks = LinkCollectionRequest(
            targetHosts: request.relevantHosts,
            includePaginationLinks: request.includePaginationControls,
            maxMatches: max(request.maxRelevantLinks * 3, request.maxRelevantLinks),
            canonicalizationStrategy: request.canonicalizationStrategy,
            collectionStrategy: request.collectionStrategy
        )
        let filteredMatches = links.filter { link in
            guard !link.isPaginationControl else {
                return false
            }
            if requestForLinks.collectionStrategy == .hackerNewsStoryLinks,
               URL(string: pageSnapshot.url)?.normalizedAgentHost == "news.ycombinator.com",
               let path = URLComponents(string: pageSnapshot.url)?.path,
               path == "/news" || path == "/news/",
               link.host == "news.ycombinator.com" {
                return false
            }
            if requestForLinks.targetHosts.isEmpty {
                return true
            }
            return requestForLinks.targetHosts.contains(link.host)
        }
        let rawResult = LinkCollectionResult(
            matches: Array(filteredMatches.prefix(requestForLinks.maxMatches)).map {
                LinkCollectionMatch(text: $0.text, url: $0.url, sourcePageURL: pageSnapshot.url)
            },
            paginationCandidates: requestForLinks.includePaginationLinks
                ? links.filter(\.isPaginationControl).map {
                    PaginationCandidate(text: $0.text, url: $0.url)
                }
                : [],
            totalLinksScanned: links.count,
            filteredOutCount: max(0, links.count - filteredMatches.count),
            pageURL: pageSnapshot.url,
            pageHost: URL(string: pageSnapshot.url)?.normalizedAgentHost ?? ""
        )
        let linkResult = LinkCollectionCanonicalizer.apply(to: rawResult, request: requestForLinks)

        return ReducedPageObservation(
            snapshot: pageSnapshot,
            request: request,
            relevantLinks: linkResult.matches.map {
                PageLink(text: $0.text, url: $0.canonicalURL, isPaginationControl: false)
            },
            paginationCandidates: request.includePaginationControls ? linkResult.paginationCandidates : [],
            totalPageLinkCount: linkResult.totalLinksScanned
        )
    }

    func click(elementId: Int, modifiers: ClickModifiers) async throws {
        recordedActions.append(.click(elementId: elementId, modifiers: modifiers))
    }

    func type(elementId: Int, text: String) async throws {
        recordedActions.append(.type(elementId: elementId, text: text))
    }

    func pressEnter() async throws {
        recordedActions.append(.pressEnter)
    }

    func scroll(deltaX: Double, deltaY: Double) async throws {
        recordedActions.append(.scroll(deltaX: deltaX, deltaY: deltaY))
    }

    func scrollToTop() async throws {
        recordedActions.append(.scrollToTop)
    }

    func scrollToBottom() async throws {
        recordedActions.append(.scrollToBottom)
    }

    func waitForLoad(timeout: TimeInterval, stableThreshold: TimeInterval) async throws {
        recordedActions.append(.waitForLoad(timeout: timeout))
    }

    func readText(elementId: Int) async throws -> String {
        recordedActions.append(.readText(elementId: elementId))
        return "Mock text content near element \(elementId)"
    }

    func revalidateElement(elementId: Int, expectedTag: String?, expectedText: String?) async throws -> Int {
        recordedActions.append(.revalidateElement(elementId: elementId))
        return elementId // Always confirms the element is still valid
    }

    func getPageLinks() async throws -> String {
        return "Example Link -> https://example.com\nAnother Link -> https://example.com/page2"
    }

    func collectLinks(_ request: LinkCollectionRequest) async throws -> LinkCollectionResult {
        if !queuedCollectionResults.isEmpty {
            let next = queuedCollectionResults.removeFirst()
            return LinkCollectionCanonicalizer.apply(to: next, request: request)
        }

        let allLinks = [
            LinkCollectionMatch(
                text: "Example Link",
                url: "https://example.com",
                sourcePageURL: currentURL
            ),
            LinkCollectionMatch(
                text: "Another Link",
                url: "https://example.com/page2",
                sourcePageURL: currentURL
            ),
        ]

        let filtered = request.targetHosts.isEmpty
            ? allLinks
            : allLinks.filter { match in
                guard let host = URL(string: match.url)?.host?.replacingOccurrences(
                    of: "^www\\.",
                    with: "",
                    options: .regularExpression
                ) else {
                    return false
                }
                return request.targetHosts.contains(host)
            }
        let strategyFiltered = request.collectionStrategy == .hackerNewsStoryLinks && currentURL.contains("news.ycombinator.com/news")
            ? filtered.filter { URL(string: $0.url)?.normalizedAgentHost != "news.ycombinator.com" }
            : filtered

        return LinkCollectionCanonicalizer.apply(
            to: LinkCollectionResult(
                matches: Array(strategyFiltered.prefix(request.maxMatches)),
                paginationCandidates: request.includePaginationLinks
                    ? [PaginationCandidate(text: "More", url: "https://example.com/page/2")]
                    : [],
                totalLinksScanned: allLinks.count,
                filteredOutCount: max(0, allLinks.count - strategyFiltered.count),
                pageURL: currentURL,
                pageHost: URL(string: currentURL)?.normalizedAgentHost ?? ""
            ),
            request: request
        )
    }

    func capturePreActionState() async -> PreActionState {
        return (url: currentURL, title: currentTitle, elementCount: 10, captchaDetected: false)
    }

    func quickDelta(before: PreActionState) async -> ActionDelta {
        return ActionDelta(
            urlChanged: before.url != currentURL,
            newURL: before.url != currentURL ? currentURL : nil,
            titleChanged: before.title != currentTitle,
            newTitle: before.title != currentTitle ? currentTitle : nil,
            elementCountBefore: before.elementCount,
            elementCountAfter: 10,
            captchaAppeared: false,
            captchaDisappeared: false
        )
    }
}

/// Mock bridge provider that returns a fixed bridge for any tab ID
@MainActor
final class MockBrowserBridgeProvider: BrowserBridgeProvider {
    let mockBridge: MockBrowserBridge

    init(bridge: MockBrowserBridge) {
        self.mockBridge = bridge
    }

    func bridge(for tabId: UUID) -> (any BrowserBridge)? {
        return mockBridge
    }
}
