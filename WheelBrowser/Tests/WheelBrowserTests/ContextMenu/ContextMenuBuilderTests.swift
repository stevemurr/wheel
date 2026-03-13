import Foundation
import Testing
@testable import WheelBrowser

@Suite("ContextMenuBuilder")
struct ContextMenuBuilderTests {
    @Test("Adds browser navigation actions as the first section")
    func addsNavigationActionsAsFirstSection() throws {
        let sections = ContextMenuBuilder.buildSections(for: .empty, canGoBack: false, canGoForward: true)
        let firstSection = try #require(sections.first)

        #expect(firstSection.items.map(\.title) == ["Back", "Forward", "Reload", "Hard Reload"])
        #expect(firstSection.items[0].isEnabled == false)
        #expect(firstSection.items[1].isEnabled == true)
        #expect(firstSection.items[2].isEnabled == true)
        #expect(firstSection.items[3].isEnabled == true)
    }

    @Test("Note actions are absent even when page context is available")
    func omitsNoteActionsForPageContext() {
        let hitTest = ContextMenuHitTest(
            linkURL: "",
            linkText: "",
            imageSrc: "",
            imageAlt: "",
            mediaSrc: "",
            mediaTagName: "",
            mediaCurrentTime: nil,
            selectedText: "",
            isEditable: false,
            pageCanonicalURL: "",
            pageURL: "https://example.com/article",
            pageTitle: "Example"
        )

        let titles = ContextMenuBuilder.buildSections(for: hitTest, canGoBack: true, canGoForward: true)
            .flatMap(\.items)
            .map(\.title)

        #expect(!titles.contains("New Note"))
    }

    @Test("Omits note actions when page context is unavailable")
    func omitsNoteActionsWithoutPageContext() {
        let titles = ContextMenuBuilder.buildSections(for: .empty, canGoBack: false, canGoForward: false)
            .flatMap(\.items)
            .map(\.title)

        #expect(!titles.contains("New Note"))
    }

    @Test("Media actions use canonical page URL instead of blob URLs")
    func prefersShareableVideoURL() throws {
        let hitTest = ContextMenuHitTest(
            linkURL: "",
            linkText: "",
            imageSrc: "",
            imageAlt: "",
            mediaSrc: "blob:https://www.youtube.com/432aa966-cca7-4d5e-9de2-9e10733721c5",
            mediaTagName: "video",
            mediaCurrentTime: 94.8,
            selectedText: "",
            isEditable: false,
            pageCanonicalURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            pageURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=abc123",
            pageTitle: "Example"
        )

        let items = ContextMenuBuilder.buildSections(for: hitTest, canGoBack: false, canGoForward: false)
            .flatMap(\.items)

        let copyAddress = try #require(items.first { $0.title == "Copy Video Address" })
        if case .copyMediaAddress(let url) = copyAddress.action {
            #expect(url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        } else {
            Issue.record("Expected Copy Video Address action")
        }

        let copyAtTime = try #require(items.first { $0.title == "Copy Video at Current Timestamp" })
        if case .copyMediaAtTimestamp(let url) = copyAtTime.action {
            #expect(url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=94s")
        } else {
            Issue.record("Expected Copy Video at Current Timestamp action")
        }
    }

    @Test("Direct media files use media fragments for timestamp copies")
    func appendsTimestampToDirectMediaURLs() throws {
        let hitTest = ContextMenuHitTest(
            linkURL: "",
            linkText: "",
            imageSrc: "",
            imageAlt: "",
            mediaSrc: "https://cdn.example.com/video.mp4",
            mediaTagName: "video",
            mediaCurrentTime: 12.9,
            selectedText: "",
            isEditable: false,
            pageCanonicalURL: "https://example.com/article",
            pageURL: "https://example.com/article",
            pageTitle: "Example"
        )

        let items = ContextMenuBuilder.buildSections(for: hitTest, canGoBack: false, canGoForward: false)
            .flatMap(\.items)

        let copyAtTime = try #require(items.first { $0.title == "Copy Video at Current Timestamp" })
        if case .copyMediaAtTimestamp(let url) = copyAtTime.action {
            #expect(url == "https://cdn.example.com/video.mp4#t=12")
        } else {
            Issue.record("Expected Copy Video at Current Timestamp action")
        }
    }
}
