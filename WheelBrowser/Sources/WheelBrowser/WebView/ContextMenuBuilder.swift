import Foundation

/// Decoded result of the JS hit-test performed on right-click.
struct ContextMenuHitTest: Codable {
    var linkURL: String
    var linkText: String
    var imageSrc: String
    var imageAlt: String
    var mediaSrc: String
    var mediaTagName: String
    var selectedText: String
    var isEditable: Bool
    var pageURL: String
    var pageTitle: String

    static let empty = ContextMenuHitTest(
        linkURL: "", linkText: "",
        imageSrc: "", imageAlt: "",
        mediaSrc: "", mediaTagName: "",
        selectedText: "", isEditable: false,
        pageURL: "", pageTitle: ""
    )
}

/// Pure-logic menu construction from a `ContextMenuHitTest`.
///
/// Returns structured `ContextMenuSection` data instead of `NSMenu` items.
/// Navigation items (Back/Forward/Reload) are handled by the card's chip bar,
/// so they are not included in the returned sections.
enum ContextMenuBuilder {

    /// Build context menu sections for the given hit-test result.
    ///
    /// Navigation actions are excluded — the card renders those as chips.
    static func buildSections(
        for hitTest: ContextMenuHitTest,
        canGoBack: Bool,
        canGoForward: Bool
    ) -> [ContextMenuSection] {
        var sections: [ContextMenuSection] = []

        // --- Link items ---
        if !hitTest.linkURL.isEmpty {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Open Link in New Tab",
                    systemImage: "plus.rectangle.on.rectangle",
                    action: .openLinkInNewTab(url: hitTest.linkURL)
                ),
                ContextMenuItem(
                    title: "Copy Link Address",
                    systemImage: "doc.on.doc",
                    action: .copyLinkAddress(url: hitTest.linkURL)
                ),
            ]))
        }

        // --- Image items ---
        if !hitTest.imageSrc.isEmpty {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Open Image in New Tab",
                    systemImage: "photo",
                    action: .openImageInNewTab(url: hitTest.imageSrc)
                ),
                ContextMenuItem(
                    title: "Save Image As\u{2026}",
                    systemImage: "square.and.arrow.down",
                    action: .saveImageAs(url: hitTest.imageSrc)
                ),
                ContextMenuItem(
                    title: "Copy Image",
                    systemImage: "doc.on.doc",
                    action: .copyImage(url: hitTest.imageSrc)
                ),
                ContextMenuItem(
                    title: "Copy Image Address",
                    systemImage: "doc.on.doc",
                    action: .copyImageAddress(url: hitTest.imageSrc)
                ),
            ]))
        }

        // --- Media items ---
        if !hitTest.mediaSrc.isEmpty {
            let label = hitTest.mediaTagName == "audio" ? "Audio" : "Video"
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Open \(label) in New Tab",
                    systemImage: "plus.rectangle.on.rectangle",
                    action: .openMediaInNewTab(url: hitTest.mediaSrc, label: label)
                ),
                ContextMenuItem(
                    title: "Copy \(label) Address",
                    systemImage: "doc.on.doc",
                    action: .copyMediaAddress(url: hitTest.mediaSrc)
                ),
            ]))
        }

        // --- Editable items ---
        if hitTest.isEditable {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(title: "Cut", systemImage: "scissors", action: .cut),
                ContextMenuItem(title: "Copy", systemImage: "doc.on.doc", action: .copy),
                ContextMenuItem(title: "Paste", systemImage: "doc.on.clipboard", action: .paste),
                ContextMenuItem(title: "Select All", systemImage: "selection.pin.in.out", action: .selectAll),
            ]))
        }

        // --- Selection items (non-editable) ---
        if !hitTest.selectedText.isEmpty && !hitTest.isEditable {
            let preview = hitTest.selectedText.count > 20
                ? String(hitTest.selectedText.prefix(20)) + "\u{2026}"
                : hitTest.selectedText
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    action: .copySelection(text: hitTest.selectedText)
                ),
                ContextMenuItem(
                    title: "Search Web for \"\(preview)\"",
                    systemImage: "magnifyingglass",
                    action: .searchWebFor(text: hitTest.selectedText)
                ),
            ]))
        }

        // --- Note capture ---
        if !hitTest.pageURL.isEmpty {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Open Today's Note",
                    systemImage: "calendar.badge.plus",
                    action: .openTodayNote
                ),
                ContextMenuItem(
                    title: "New Note From Page",
                    systemImage: "note.text.badge.plus",
                    action: .newNoteFromPage
                ),
            ]))
        }

        return sections
    }
}
