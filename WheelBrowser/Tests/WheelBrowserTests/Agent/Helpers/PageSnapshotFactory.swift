import Foundation
@testable import WheelBrowser

/// Factory for creating PageSnapshot instances in tests
enum PageSnapshotFactory {

    /// An empty page snapshot
    static func empty(url: String = "about:blank", title: String = "") -> PageSnapshot {
        PageSnapshot(
            url: url,
            title: title,
            elements: [],
            scrollPosition: .init(x: 0, y: 0, maxX: 0, maxY: 0),
            viewportSize: .init(width: 1280, height: 800)
        )
    }

    /// A search engine homepage with a search box
    static func searchPage(
        url: String = "https://duckduckgo.com",
        title: String = "DuckDuckGo"
    ) -> PageSnapshot {
        PageSnapshot(
            url: url,
            title: title,
            elements: [
                PageElement(
                    id: 0,
                    tag: "input",
                    role: "searchbox",
                    text: nil,
                    placeholder: "Search the web without being tracked",
                    ariaLabel: "Search",
                    href: nil,
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 400, y: 300, width: 500, height: 40)
                ),
                PageElement(
                    id: 1,
                    tag: "button",
                    role: "button",
                    text: "Search",
                    placeholder: nil,
                    ariaLabel: "Search",
                    href: nil,
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 910, y: 300, width: 60, height: 40)
                )
            ],
            scrollPosition: .init(x: 0, y: 0, maxX: 0, maxY: 500),
            viewportSize: .init(width: 1280, height: 800),
            headings: [PageHeading(level: 1, text: "DuckDuckGo")]
        )
    }

    /// A search results page
    static func searchResultsPage(
        url: String = "https://duckduckgo.com/?q=Swift+programming",
        title: String = "Swift programming at DuckDuckGo",
        resultTitles: [String] = ["Swift.org", "Swift (programming language) - Wikipedia", "Learn Swift"]
    ) -> PageSnapshot {
        var elements: [PageElement] = [
            PageElement(
                id: 0,
                tag: "input",
                role: "searchbox",
                text: nil,
                placeholder: "Search the web without being tracked",
                ariaLabel: "Search",
                href: nil,
                isVisible: true,
                isEnabled: true,
                boundingBox: .init(x: 100, y: 10, width: 500, height: 40)
            )
        ]

        for (index, resultTitle) in resultTitles.enumerated() {
            elements.append(PageElement(
                id: index + 1,
                tag: "a",
                role: "link",
                text: resultTitle,
                placeholder: nil,
                ariaLabel: nil,
                href: "https://example.com/result\(index)",
                isVisible: true,
                isEnabled: true,
                boundingBox: .init(x: 100, y: Double(100 + index * 80), width: 600, height: 30)
            ))
        }

        return PageSnapshot(
            url: url,
            title: title,
            elements: elements,
            scrollPosition: .init(x: 0, y: 0, maxX: 0, maxY: 2000),
            viewportSize: .init(width: 1280, height: 800),
            headings: [PageHeading(level: 1, text: "Results for Swift programming")],
            contentSummary: "Swift programming language results. Swift.org is the official site..."
        )
    }

    /// A Wikipedia article page
    static func wikipediaArticle(
        url: String = "https://en.wikipedia.org/wiki/Alan_Turing",
        title: String = "Alan Turing - Wikipedia",
        contentSummary: String = "Alan Mathison Turing was an English mathematician, computer scientist, logician, cryptanalyst, philosopher, and theoretical biologist."
    ) -> PageSnapshot {
        PageSnapshot(
            url: url,
            title: title,
            elements: [
                PageElement(
                    id: 0,
                    tag: "input",
                    role: "searchbox",
                    text: nil,
                    placeholder: "Search Wikipedia",
                    ariaLabel: "Search Wikipedia",
                    href: nil,
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 800, y: 10, width: 300, height: 30)
                ),
                PageElement(
                    id: 1,
                    tag: "a",
                    role: "link",
                    text: "Contents",
                    placeholder: nil,
                    ariaLabel: nil,
                    href: "#Contents",
                    isVisible: true,
                    isEnabled: true,
                    boundingBox: .init(x: 100, y: 200, width: 80, height: 20)
                )
            ],
            scrollPosition: .init(x: 0, y: 0, maxX: 0, maxY: 5000),
            viewportSize: .init(width: 1280, height: 800),
            headings: [
                PageHeading(level: 1, text: "Alan Turing"),
                PageHeading(level: 2, text: "Early life and education"),
                PageHeading(level: 2, text: "Career and research")
            ],
            contentSummary: contentSummary
        )
    }

    /// A page with a captcha challenge
    static func captchaPage(
        url: String = "https://example.com/protected",
        captchaType: String = "Cloudflare Challenge"
    ) -> PageSnapshot {
        PageSnapshot(
            url: url,
            title: "Just a moment...",
            elements: [],
            scrollPosition: .init(x: 0, y: 0, maxX: 0, maxY: 0),
            viewportSize: .init(width: 1280, height: 800),
            captchaDetected: true,
            captchaType: captchaType
        )
    }
}
