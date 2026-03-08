import Foundation
import Testing
@testable import WheelBrowser

@Suite("Agent Context Reduction")
struct AgentContextReductionTests {
    @Test("Task intent parser extracts collection constraints")
    func parsesCollectionIntent() {
        let intent = AgentTaskIntent.parse(
            task: "On Hacker News, scan the first 10 pages and create a list of all the arxiv links with unique URLs."
        )

        #expect(intent.collectionMode == .paginatedLinks)
        #expect(intent.seedURL == "https://news.ycombinator.com/news")
        #expect(intent.sourceHosts == ["news.ycombinator.com"])
        #expect(intent.targetHosts == ["arxiv.org"])
        #expect(intent.pageLimit == 10)
        #expect(intent.requiresUniqueURLs)
        #expect(intent.canonicalizationStrategy == .arxiv)
        #expect(intent.snapshotRequest.relevantHosts == ["arxiv.org"])
        #expect(intent.linkCollectionRequest?.targetHosts == ["arxiv.org"])
    }

    @Test("Reduced observation keeps relevant links and pagination while omitting irrelevant content")
    func reducedObservationPreservesRelevantContent() {
        let snapshot = PageSnapshot(
            url: "https://news.ycombinator.com/news",
            title: "Hacker News",
            elements: [
                PageElement(
                    id: 1,
                    tag: "a",
                    role: "link",
                    text: "Paper 1",
                    placeholder: nil,
                    ariaLabel: nil,
                    href: "https://arxiv.org/abs/1234.5678",
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 20, y: 120, width: 300, height: 20)
                ),
                PageElement(
                    id: 2,
                    tag: "button",
                    role: "button",
                    text: "More",
                    placeholder: nil,
                    ariaLabel: "Next page",
                    href: nil,
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 20, y: 720, width: 80, height: 24)
                ),
                PageElement(
                    id: 3,
                    tag: "a",
                    role: "link",
                    text: "Other link",
                    placeholder: nil,
                    ariaLabel: nil,
                    href: "https://example.com/post",
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 20, y: 180, width: 280, height: 20)
                ),
                PageElement(
                    id: 4,
                    tag: "input",
                    role: "searchbox",
                    text: nil,
                    placeholder: "Search",
                    ariaLabel: "Search",
                    href: nil,
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 20, y: 40, width: 240, height: 30)
                ),
            ],
            scrollPosition: .init(x: 0, y: 400, maxX: 0, maxY: 2000),
            viewportSize: .init(width: 1280, height: 800),
            headings: [PageHeading(level: 1, text: "Hacker News")],
            contentSummary: "A long list of stories."
        )

        let observation = ReducedPageObservation(
            snapshot: snapshot,
            request: SnapshotRequest(
                maxInteractiveElements: 2,
                includeHeadings: false,
                includeContentSummary: false,
                includePaginationControls: true,
                relevantHosts: ["arxiv.org"],
                maxRelevantLinks: 1,
                canonicalizationStrategy: .arxiv
            ),
            relevantLinks: [
                PageLink(text: "Paper 1", url: "https://arxiv.org/abs/1234.5678", isPaginationControl: false),
                PageLink(text: "Paper 2", url: "https://arxiv.org/abs/2345.6789", isPaginationControl: false),
                PageLink(text: "Paper 1 duplicate", url: "https://arxiv.org/abs/1234.5678", isPaginationControl: false),
            ],
            paginationCandidates: [
                PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=2"),
            ],
            totalPageLinkCount: 20
        )

        #expect(observation.relevantLinks.count == 1)
        #expect(observation.totalRelevantLinkCount == 2)
        #expect(observation.omittedRelevantLinkCount == 1)
        #expect(observation.paginationCandidates.count == 1)
        #expect(observation.interactiveElements.count == 2)
        #expect(observation.interactiveElements[0].href == "https://arxiv.org/abs/1234.5678")
        #expect(observation.interactiveElements[1].text == "More")

        let rendered = observation.textRepresentation
        #expect(rendered.contains("Relevant Links (1/2):"))
        #expect(rendered.contains("Paper 1 -> https://arxiv.org/abs/1234.5678"))
        #expect(rendered.contains("... 1 more matching links omitted"))
        #expect(rendered.contains("Pagination Controls:"))
        #expect(rendered.contains("More -> https://news.ycombinator.com/news?p=2"))
        #expect(!rendered.contains("Content Summary:"))
        #expect(!rendered.contains("Headings:"))
    }

    @Test("Canonicalizer normalizes arxiv abs and pdf links")
    func canonicalizesArxivLinks() {
        let request = LinkCollectionRequest(
            targetHosts: ["arxiv.org"],
            includePaginationLinks: true,
            maxMatches: 10,
            canonicalizationStrategy: .arxiv
        )
        let raw = LinkCollectionResult(
            matches: [
                LinkCollectionMatch(
                    text: "Paper 1",
                    url: "https://arxiv.org/pdf/1234.5678.pdf",
                    sourcePageURL: "https://news.ycombinator.com/news"
                ),
                LinkCollectionMatch(
                    text: "Paper 1 abstract",
                    url: "https://arxiv.org/abs/1234.5678",
                    sourcePageURL: "https://news.ycombinator.com/news?p=2"
                ),
            ],
            paginationCandidates: [],
            totalLinksScanned: 2,
            filteredOutCount: 0,
            pageURL: "https://news.ycombinator.com/news",
            pageHost: "news.ycombinator.com"
        )

        let canonicalized = LinkCollectionCanonicalizer.apply(to: raw, request: request)

        #expect(canonicalized.matches[0].canonicalID == "1234.5678")
        #expect(canonicalized.matches[0].canonicalURL == "https://arxiv.org/abs/1234.5678")
        #expect(canonicalized.matches[1].canonicalURL == "https://arxiv.org/abs/1234.5678")
    }

    @Test("Crawl session rejects revisiting the same pagination target")
    func rejectsRepeatedPaginationVisit() {
        let intent = AgentTaskIntent.parse(
            task: "On Hacker News, scan the first 5 pages and create a list of all the arxiv links."
        )
        var session = AgentCrawlSession(intent: intent)
        session.observePage(
            url: "https://news.ycombinator.com/news",
            paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=2")]
        )

        let candidate = session.resolvePaginationCandidate(preferredURL: nil)
        #expect(candidate?.url == "https://news.ycombinator.com/news?p=2")
        let firstVisit = session.registerPaginationVisit(candidate!)
        let secondVisit = session.registerPaginationVisit(candidate!)
        #expect(firstVisit)
        #expect(!secondVisit)
    }

    @Test("Collection accumulator deduplicates and emits artifacts")
    func accumulatorDeduplicatesAndBuildsArtifacts() throws {
        var accumulator = AgentCollectionAccumulator()

        let firstDelta = accumulator.absorb(
            LinkCollectionResult(
                matches: [
                    LinkCollectionMatch(
                        text: "Paper 1",
                        url: "https://arxiv.org/pdf/1234.5678.pdf",
                        canonicalURL: "https://arxiv.org/abs/1234.5678",
                        canonicalID: "1234.5678",
                        sourcePageURL: "https://news.ycombinator.com/news",
                        pageIndex: 1
                    ),
                    LinkCollectionMatch(
                        text: "Paper 2",
                        url: "https://arxiv.org/abs/2345.6789",
                        canonicalURL: "https://arxiv.org/abs/2345.6789",
                        canonicalID: "2345.6789",
                        sourcePageURL: "https://news.ycombinator.com/news",
                        pageIndex: 1
                    ),
                ],
                paginationCandidates: [],
                totalLinksScanned: 30,
                filteredOutCount: 28,
                pageURL: "https://news.ycombinator.com/news",
                pageHost: "news.ycombinator.com"
            )
        )

        let secondDelta = accumulator.absorb(
            LinkCollectionResult(
                matches: [
                    LinkCollectionMatch(
                        text: "Paper 2 again",
                        url: "https://arxiv.org/pdf/2345.6789.pdf",
                        canonicalURL: "https://arxiv.org/abs/2345.6789",
                        canonicalID: "2345.6789",
                        sourcePageURL: "https://news.ycombinator.com/news?p=2",
                        pageIndex: 2
                    ),
                    LinkCollectionMatch(
                        text: "Paper 3",
                        url: "https://arxiv.org/abs/3456.7890",
                        canonicalURL: "https://arxiv.org/abs/3456.7890",
                        canonicalID: "3456.7890",
                        sourcePageURL: "https://news.ycombinator.com/news?p=2",
                        pageIndex: 2
                    ),
                ],
                paginationCandidates: [],
                totalLinksScanned: 30,
                filteredOutCount: 28,
                pageURL: "https://news.ycombinator.com/news?p=2",
                pageHost: "news.ycombinator.com"
            )
        )

        #expect(firstDelta.added.count == 2)
        #expect(firstDelta.duplicateCount == 0)
        #expect(firstDelta.totalUniqueCount == 2)
        #expect(secondDelta.added.count == 1)
        #expect(secondDelta.duplicateCount == 1)
        #expect(secondDelta.totalUniqueCount == 3)
        #expect(accumulator.totalUniqueCount == 3)
        #expect(accumulator.summaryText().contains("Collected links: 3 unique URLs."))

        let artifacts = accumulator.artifacts(title: "arXiv")
        #expect(artifacts.count == 2)
        #expect(artifacts[0].type == .markdown)
        #expect(artifacts[0].content.contains("- [Paper 1](https://arxiv.org/abs/1234.5678)"))
        #expect(artifacts[1].type == .json)

        let decoded = try JSONDecoder().decode([LinkCollectionMatch].self, from: Data(artifacts[1].content.utf8))
        #expect(decoded.count == 3)
    }
}
