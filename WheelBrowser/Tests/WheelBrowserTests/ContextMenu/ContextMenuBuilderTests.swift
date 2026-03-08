import Foundation
import Testing
@testable import WheelBrowser

@Suite("ContextMenuBuilder")
struct ContextMenuBuilderTests {
    @Test("Adds note actions when page context is available")
    func addsNoteActionsForPageContext() {
        let hitTest = ContextMenuHitTest(
            linkURL: "",
            linkText: "",
            imageSrc: "",
            imageAlt: "",
            mediaSrc: "",
            mediaTagName: "",
            selectedText: "",
            isEditable: false,
            pageURL: "https://example.com/article",
            pageTitle: "Example"
        )

        let titles = ContextMenuBuilder.buildSections(for: hitTest, canGoBack: true, canGoForward: true)
            .flatMap(\.items)
            .map(\.title)

        #expect(titles.contains("New Note"))
    }

    @Test("Omits note actions when page context is unavailable")
    func omitsNoteActionsWithoutPageContext() {
        let titles = ContextMenuBuilder.buildSections(for: .empty, canGoBack: false, canGoForward: false)
            .flatMap(\.items)
            .map(\.title)

        #expect(!titles.contains("New Note"))
    }
}
