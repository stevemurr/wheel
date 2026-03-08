import Foundation
import LanguageModelContextKit
import Testing
@testable import WheelBrowser

@Suite("Agent Collection Execution")
struct AgentCollectionExecutionTests {
    @Test("Engine auto-collects and stops at the requested page budget without explicit collect or done actions")
    @MainActor
    func autoCollectsAndStopsAtRequestedPageBudget() async {
        let browserState = BrowserState()
        let bridge = MockBrowserBridge(
            snapshots: [
                pageSnapshot(url: "https://news.ycombinator.com/news", nextPageURL: "https://news.ycombinator.com/news?p=2"),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=2", nextPageURL: "https://news.ycombinator.com/news?p=3"),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=3", nextPageURL: "https://news.ycombinator.com/news?p=4"),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=4", nextPageURL: "https://news.ycombinator.com/news?p=5"),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=5", nextPageURL: "https://news.ycombinator.com/news?p=6"),
            ],
            initialURL: "about:blank",
            initialTitle: "Blank",
            queuedCollectionResults: [
                linkResult(
                    pageURL: "https://news.ycombinator.com/news",
                    matches: [
                        LinkCollectionMatch(
                            text: "Interesting Link 1",
                            url: "https://example.com/story-1",
                            sourcePageURL: "https://news.ycombinator.com/news"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=2")]
                ),
                linkResult(
                    pageURL: "https://news.ycombinator.com/news?p=2",
                    matches: [
                        LinkCollectionMatch(
                            text: "Interesting Link 2",
                            url: "https://example.com/story-2",
                            sourcePageURL: "https://news.ycombinator.com/news?p=2"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=3")]
                ),
                linkResult(
                    pageURL: "https://news.ycombinator.com/news?p=3",
                    matches: [
                        LinkCollectionMatch(
                            text: "Interesting Link 3",
                            url: "https://example.com/story-3",
                            sourcePageURL: "https://news.ycombinator.com/news?p=3"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=4")]
                ),
                linkResult(
                    pageURL: "https://news.ycombinator.com/news?p=4",
                    matches: [
                        LinkCollectionMatch(
                            text: "Interesting Link 4",
                            url: "https://example.com/story-4",
                            sourcePageURL: "https://news.ycombinator.com/news?p=4"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=5")]
                ),
                linkResult(
                    pageURL: "https://news.ycombinator.com/news?p=5",
                    matches: [
                        LinkCollectionMatch(
                            text: "Interesting Link 5",
                            url: "https://example.com/story-5",
                            sourcePageURL: "https://news.ycombinator.com/news?p=5"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=6")]
                ),
            ]
        )
        let contextService = MockWheelModelContextService(
            decisions: [
                decision(thought: "Move to page 2.", action: .advancePagination(url: nil)),
                decision(thought: "Move to page 3.", action: .advancePagination(url: nil)),
                decision(thought: "Move to page 4.", action: .advancePagination(url: nil)),
                decision(thought: "Move to page 5.", action: .advancePagination(url: nil)),
                decision(thought: "This should never be used.", action: .advancePagination(url: nil)),
            ]
        )
        let engine = AgentEngine(
            browserState: browserState,
            contextService: contextService,
            bridgeProvider: MockBrowserBridgeProvider(bridge: bridge)
        )
        engine.maxSteps = 12

        let result = await engine.run(task: "go to hacker news and create a list of the most interesting links from the first 5 pages")

        #expect(result.success)
        #expect(result.collection?.pagesScanned == 5)
        #expect(result.collection?.pageLimit == 5)
        #expect(result.collection?.totalUniqueCount == 5)
        #expect(result.collection?.items.count == 5)
        #expect(!result.artifacts.isEmpty)
        #expect(result.summary.contains("5 requested pages"))
        #expect(await contextService.servedDecisionCount() == 4)
    }

    @Test("Engine collects canonicalized links across paginated pages")
    @MainActor
    func collectsAcrossPages() async {
        let browserState = BrowserState()
        let bridge = MockBrowserBridge(
            snapshots: [
                pageSnapshot(url: "https://news.ycombinator.com/news", nextPageURL: "https://news.ycombinator.com/news?p=2"),
                pageSnapshot(url: "https://news.ycombinator.com/news", nextPageURL: "https://news.ycombinator.com/news?p=2"),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=2", nextPageURL: nil),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=2", nextPageURL: nil),
            ],
            initialURL: "https://news.ycombinator.com/news",
            initialTitle: "Hacker News",
            queuedCollectionResults: [
                linkResult(
                    pageURL: "https://news.ycombinator.com/news",
                    matches: [
                        LinkCollectionMatch(
                            text: "Paper 1",
                            url: "https://arxiv.org/pdf/1234.5678.pdf",
                            sourcePageURL: "https://news.ycombinator.com/news"
                        ),
                        LinkCollectionMatch(
                            text: "Paper 2",
                            url: "https://arxiv.org/abs/2345.6789",
                            sourcePageURL: "https://news.ycombinator.com/news"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=2")]
                ),
                linkResult(
                    pageURL: "https://news.ycombinator.com/news?p=2",
                    matches: [
                        LinkCollectionMatch(
                            text: "Paper 2 duplicate",
                            url: "https://arxiv.org/pdf/2345.6789.pdf",
                            sourcePageURL: "https://news.ycombinator.com/news?p=2"
                        ),
                        LinkCollectionMatch(
                            text: "Paper 3",
                            url: "https://arxiv.org/abs/3456.7890",
                            sourcePageURL: "https://news.ycombinator.com/news?p=2"
                        ),
                    ],
                    paginationCandidates: []
                ),
            ]
        )
        let contextService = MockWheelModelContextService(
            decisions: [
                decision(thought: "Collect the first page of results.", action: .collectLinks),
                decision(thought: "Advance to the next page.", action: .advancePagination(url: nil)),
                decision(thought: "Collect the second page of results.", action: .collectLinks),
                decision(thought: "The requested page budget is complete.", action: .done(summary: "Collected the arXiv links from the requested pages.")),
            ]
        )
        let engine = AgentEngine(
            browserState: browserState,
            contextService: contextService,
            bridgeProvider: MockBrowserBridgeProvider(bridge: bridge)
        )
        engine.maxSteps = 8

        let result = await engine.run(task: "Go to Hacker News, and create a list of all arxiv papers linked in the first 2 pages")

        #expect(result.success)
        #expect(result.collection?.pagesScanned == 2)
        #expect(result.collection?.pageLimit == 2)
        #expect(result.collection?.totalUniqueCount == 3)
        #expect(result.collection?.items.count == 3)
        #expect(result.collection?.items.map(\.pageIndex) == [1, 1, 2])
        #expect(result.collection?.items.map(\.canonicalURL) == [
            "https://arxiv.org/abs/1234.5678",
            "https://arxiv.org/abs/2345.6789",
            "https://arxiv.org/abs/3456.7890",
        ])
        #expect(result.artifacts.count == 2)
        #expect(result.artifacts[0].content.contains("https://arxiv.org/abs/1234.5678"))
        #expect(engine.lastResult?.collection?.pagesScanned == 2)
    }

    @Test("Engine rejects done until the requested page budget is reached")
    @MainActor
    func rejectsDoneBeforePageBudget() async {
        let browserState = BrowserState()
        let bridge = MockBrowserBridge(
            snapshots: [
                pageSnapshot(url: "https://news.ycombinator.com/news", nextPageURL: "https://news.ycombinator.com/news?p=2"),
                pageSnapshot(url: "https://news.ycombinator.com/news", nextPageURL: "https://news.ycombinator.com/news?p=2"),
                pageSnapshot(url: "https://news.ycombinator.com/news", nextPageURL: "https://news.ycombinator.com/news?p=2"),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=2", nextPageURL: nil),
                pageSnapshot(url: "https://news.ycombinator.com/news?p=2", nextPageURL: nil),
            ],
            initialURL: "https://news.ycombinator.com/news",
            initialTitle: "Hacker News",
            queuedCollectionResults: [
                linkResult(
                    pageURL: "https://news.ycombinator.com/news",
                    matches: [
                        LinkCollectionMatch(
                            text: "Paper 1",
                            url: "https://arxiv.org/abs/1234.5678",
                            sourcePageURL: "https://news.ycombinator.com/news"
                        ),
                    ],
                    paginationCandidates: [PaginationCandidate(text: "More", url: "https://news.ycombinator.com/news?p=2")]
                ),
                linkResult(
                    pageURL: "https://news.ycombinator.com/news?p=2",
                    matches: [
                        LinkCollectionMatch(
                            text: "Paper 2",
                            url: "https://arxiv.org/abs/2345.6789",
                            sourcePageURL: "https://news.ycombinator.com/news?p=2"
                        ),
                    ],
                    paginationCandidates: []
                ),
            ]
        )
        let contextService = MockWheelModelContextService(
            decisions: [
                decision(thought: "Collect the first page.", action: .collectLinks),
                decision(thought: "We have enough.", action: .done(summary: "Done early")),
                decision(thought: "Continue to the next page.", action: .advancePagination(url: nil)),
                decision(thought: "Collect the second page.", action: .collectLinks),
                decision(thought: "Now the requested pages are scanned.", action: .done(summary: "Finished collecting the requested pages.")),
            ]
        )
        let engine = AgentEngine(
            browserState: browserState,
            contextService: contextService,
            bridgeProvider: MockBrowserBridgeProvider(bridge: bridge)
        )
        engine.maxSteps = 10

        let result = await engine.run(task: "Go to Hacker News, and create a list of all arxiv papers linked in the first 2 pages")

        #expect(result.success)
        #expect(result.collection?.pagesScanned == 2)
        #expect(result.steps.contains(where: { step in
            step.type == .error && step.content.contains("You have only scanned 1 of 2 requested pages")
        }))
    }

    @Test("MCP agent_run response includes structured collection payload")
    func mcpResponseIncludesCollection() {
        let result = AgentResult(
            success: true,
            summary: "Collected 2 links.",
            steps: [],
            artifacts: [
                ChatArtifact(title: "Collected Links", language: "md", content: "- [Paper](https://arxiv.org/abs/1234.5678)", type: .markdown)
            ],
            collection: AgentCollectionSummary(
                pagesScanned: 2,
                pageLimit: 2,
                sourceHosts: ["news.ycombinator.com"],
                targetHosts: ["arxiv.org"],
                totalUniqueCount: 2,
                items: [
                    LinkCollectionMatch(
                        text: "Paper 1",
                        url: "https://arxiv.org/abs/1234.5678",
                        canonicalURL: "https://arxiv.org/abs/1234.5678",
                        canonicalID: "1234.5678",
                        sourcePageURL: "https://news.ycombinator.com/news",
                        pageIndex: 1
                    )
                ]
            )
        )

        let payload = MCPToolDefinitions.agentRunResponse(result)
        let collection = payload["collection"] as? [String: Any]
        let items = collection?["items"] as? [[String: Any]]
        let artifacts = payload["artifacts"] as? [[String: Any]]

        #expect(payload["success"] as? Bool == true)
        #expect(payload["summary"] as? String == "Collected 2 links.")
        #expect(collection?["pagesScanned"] as? Int == 2)
        #expect(collection?["totalUniqueCount"] as? Int == 2)
        #expect(items?.first?["canonicalURL"] as? String == "https://arxiv.org/abs/1234.5678")
        #expect(artifacts?.first?["type"] as? String == "markdown")
    }
}

private actor MockWheelModelContextService: WheelModelContextServing {
    private var decisions: [GeneratedAgentDecision]
    private var servedDecisions = 0

    init(decisions: [GeneratedAgentDecision]) {
        self.decisions = decisions
    }

    func availabilityStatus() async -> LMAvailabilityStatus {
        .available
    }

    func openChatThread(conversationId: UUID, instructions: String) async throws {}

    func importChatThread(
        conversationId: UUID,
        instructions: String,
        turns: [LMNormalizedTurn],
        durableMemory: [LMDurableMemoryRecord],
        replaceExisting: Bool
    ) async throws {}

    func streamChatResponse(
        conversationId: UUID,
        prompt: String
    ) async throws -> AsyncThrowingStream<WheelChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func openAgentThread(tabId: UUID, runId: UUID, instructions: String) async throws -> String {
        WheelModelContextService.agentThreadID(tabId: tabId, runId: runId)
    }

    func streamAgentDecision(
        prompt: String,
        threadID: String
    ) async throws -> AsyncThrowingStream<WheelAgentDecisionStreamEvent, Error> {
        servedDecisions += 1
        let nextDecision = decisions.isEmpty
            ? decision(thought: "Stop after exhausting test decisions.", action: .done(summary: "No more decisions"))
            : decisions.removeFirst()
        let response = LMManagedStructuredResponse(
            content: nextDecision,
            transcriptText: nextDecision.transcriptSummary,
            budget: BudgetReport(
                accuracy: .exact,
                contextWindowTokens: 4096,
                estimatedInputTokens: 0,
                reservedOutputTokens: 0,
                projectedTotalTokens: 0,
                softLimitTokens: 4096,
                emergencyLimitTokens: 4096,
                breakdown: [:]
            ),
            compaction: nil,
            bridge: nil
        )

        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(response))
            continuation.finish()
        }
    }

    func servedDecisionCount() -> Int {
        servedDecisions
    }

    func appendAgentTurns(_ turns: [LMNormalizedTurn], threadID: String) async throws {}

    func generateSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> LMManagedStructuredResponse<GeneratedSummaryResponse> {
        fatalError("Not used in agent execution tests")
    }

    func streamSummary(
        requestID: UUID,
        prompt: String,
        instructions: String
    ) async throws -> AsyncThrowingStream<WheelSummaryStreamEvent, Error> {
        fatalError("Not used in agent execution tests")
    }

    func generateWidgetPlan(
        requestID: UUID,
        prompt: String,
        instructions: String,
        transcriptRenderer: (@Sendable (GeneratedWidgetPlan) -> String)?
    ) async throws -> LMManagedStructuredResponse<GeneratedWidgetPlan> {
        fatalError("Not used in agent execution tests")
    }

    func threadState(threadID: String) async throws -> LMPersistedThreadState {
        LMPersistedThreadState(threadID: threadID, instructions: nil, localeIdentifier: nil, model: .default)
    }

    func resetThread(threadID: String) async throws {}
}

private func decision(thought: String, action: AgentAction) -> GeneratedAgentDecision {
    GeneratedAgentDecision(
        thought: thought,
        action: GeneratedAgentAction(from: action)
    )
}

private func pageSnapshot(url: String, nextPageURL: String?) -> PageSnapshot {
    var elements: [PageElement] = [
        PageElement(
            id: 0,
            tag: "a",
            role: "link",
            text: "Story 1",
            placeholder: nil,
            ariaLabel: nil,
            href: "https://news.ycombinator.com/item?id=1",
            isVisible: true,
            isEnabled: true,
            boundingBox: .init(x: 20, y: 120, width: 300, height: 20)
        ),
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
            boundingBox: .init(x: 20, y: 150, width: 300, height: 20)
        ),
        PageElement(
            id: 2,
            tag: "a",
            role: "link",
            text: "Comments",
            placeholder: nil,
            ariaLabel: nil,
            href: "https://news.ycombinator.com/item?id=1",
            isVisible: true,
            isEnabled: true,
            boundingBox: .init(x: 20, y: 180, width: 300, height: 20)
        ),
        PageElement(
            id: 3,
            tag: "input",
            role: "searchbox",
            text: nil,
            placeholder: "Search",
            ariaLabel: "Search",
            href: nil,
            isVisible: true,
            isEnabled: true,
            boundingBox: .init(x: 20, y: 40, width: 200, height: 30)
        ),
    ]

    if let nextPageURL {
        elements.append(
            PageElement(
                id: 4,
                tag: "a",
                role: "link",
                text: "More",
                placeholder: nil,
                ariaLabel: nil,
                href: nextPageURL,
                isVisible: true,
                isEnabled: true,
                boundingBox: .init(x: 20, y: 720, width: 80, height: 24)
            )
        )
    }

    return PageSnapshot(
        url: url,
        title: "Hacker News",
        elements: elements,
        scrollPosition: .init(x: 0, y: 0, maxX: 0, maxY: 2000),
        viewportSize: .init(width: 1280, height: 800),
        headings: [PageHeading(level: 1, text: "Hacker News")],
        contentSummary: "A list of Hacker News stories."
    )
}

private func linkResult(
    pageURL: String,
    matches: [LinkCollectionMatch],
    paginationCandidates: [PaginationCandidate]
) -> LinkCollectionResult {
    LinkCollectionResult(
        matches: matches,
        paginationCandidates: paginationCandidates,
        totalLinksScanned: matches.count + paginationCandidates.count,
        filteredOutCount: 0,
        pageURL: pageURL,
        pageHost: URL(string: pageURL)?.normalizedAgentHost ?? ""
    )
}
