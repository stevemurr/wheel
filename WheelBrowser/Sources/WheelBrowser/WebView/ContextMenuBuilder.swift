import AppKit
import WebKit

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
/// Each `NSMenuItem` stores its URL or text in `representedObject` so that
/// action handlers never need to re-read hit-test state.
enum ContextMenuBuilder {

    // MARK: - Cached SF Symbol icons

    private static let newTabIcon: NSImage? = makeIcon("plus.rectangle.on.rectangle", "Open in new tab")
    private static let copyIcon: NSImage? = makeIcon("doc.on.doc", "Copy")
    private static let cutIcon: NSImage? = makeIcon("scissors", "Cut")
    private static let pasteIcon: NSImage? = makeIcon("doc.on.clipboard", "Paste")
    private static let selectAllIcon: NSImage? = makeIcon("selection.pin.in.out", "Select all")
    private static let saveIcon: NSImage? = makeIcon("square.and.arrow.down", "Save")
    private static let searchIcon: NSImage? = makeIcon("magnifyingglass", "Search")
    private static let backIcon: NSImage? = makeIcon("chevron.left", "Back")
    private static let forwardIcon: NSImage? = makeIcon("chevron.right", "Forward")
    private static let reloadIcon: NSImage? = makeIcon("arrow.clockwise", "Reload")
    private static let imageIcon: NSImage? = makeIcon("photo", "Image")

    private static func makeIcon(_ name: String, _ description: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)
        img?.size = NSSize(width: 16, height: 16)
        img?.isTemplate = true
        return img
    }

    // MARK: - Menu building

    /// Build a context menu for the given hit-test result.
    ///
    /// - Parameters:
    ///   - hitTest: The decoded JS hit-test result.
    ///   - target: The `BrowserWebView` that will handle menu actions.
    /// - Returns: A fully constructed `NSMenu`.
    static func buildMenu(for hitTest: ContextMenuHitTest, target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        // --- Link items ---
        if !hitTest.linkURL.isEmpty {
            let openTab = NSMenuItem(title: "Open Link in New Tab",
                                     action: #selector(BrowserWebView.contextAction_openLinkInNewTab(_:)),
                                     keyEquivalent: "")
            openTab.target = target
            openTab.image = newTabIcon
            openTab.representedObject = hitTest.linkURL
            menu.addItem(openTab)

            let copyLink = NSMenuItem(title: "Copy Link Address",
                                      action: #selector(BrowserWebView.contextAction_copyLinkAddress(_:)),
                                      keyEquivalent: "")
            copyLink.target = target
            copyLink.image = copyIcon
            copyLink.representedObject = hitTest.linkURL
            menu.addItem(copyLink)

            menu.addItem(.separator())
        }

        // --- Image items ---
        if !hitTest.imageSrc.isEmpty {
            let openImg = NSMenuItem(title: "Open Image in New Tab",
                                     action: #selector(BrowserWebView.contextAction_openImageInNewTab(_:)),
                                     keyEquivalent: "")
            openImg.target = target
            openImg.image = imageIcon
            openImg.representedObject = hitTest.imageSrc
            menu.addItem(openImg)

            let saveImg = NSMenuItem(title: "Save Image As\u{2026}",
                                     action: #selector(BrowserWebView.contextAction_saveImageAs(_:)),
                                     keyEquivalent: "")
            saveImg.target = target
            saveImg.image = saveIcon
            saveImg.representedObject = hitTest.imageSrc
            menu.addItem(saveImg)

            let copyImg = NSMenuItem(title: "Copy Image",
                                     action: #selector(BrowserWebView.contextAction_copyImage(_:)),
                                     keyEquivalent: "")
            copyImg.target = target
            copyImg.image = copyIcon
            copyImg.representedObject = hitTest.imageSrc
            menu.addItem(copyImg)

            let copyImgAddr = NSMenuItem(title: "Copy Image Address",
                                         action: #selector(BrowserWebView.contextAction_copyImageAddress(_:)),
                                         keyEquivalent: "")
            copyImgAddr.target = target
            copyImgAddr.image = copyIcon
            copyImgAddr.representedObject = hitTest.imageSrc
            menu.addItem(copyImgAddr)

            menu.addItem(.separator())
        }

        // --- Media items ---
        if !hitTest.mediaSrc.isEmpty {
            let label = hitTest.mediaTagName == "audio" ? "Audio" : "Video"

            let openMedia = NSMenuItem(title: "Open \(label) in New Tab",
                                       action: #selector(BrowserWebView.contextAction_openMediaInNewTab(_:)),
                                       keyEquivalent: "")
            openMedia.target = target
            openMedia.image = newTabIcon
            openMedia.representedObject = hitTest.mediaSrc
            menu.addItem(openMedia)

            let copyAddr = NSMenuItem(title: "Copy \(label) Address",
                                      action: #selector(BrowserWebView.contextAction_copyMediaAddress(_:)),
                                      keyEquivalent: "")
            copyAddr.target = target
            copyAddr.image = copyIcon
            copyAddr.representedObject = hitTest.mediaSrc
            menu.addItem(copyAddr)

            menu.addItem(.separator())
        }

        // --- Editable items ---
        if hitTest.isEditable {
            let cut = NSMenuItem(title: "Cut", action: #selector(BrowserWebView.contextAction_cut(_:)), keyEquivalent: "")
            cut.target = target
            cut.image = cutIcon
            menu.addItem(cut)

            let copy = NSMenuItem(title: "Copy", action: #selector(BrowserWebView.contextAction_copy(_:)), keyEquivalent: "")
            copy.target = target
            copy.image = copyIcon
            menu.addItem(copy)

            let paste = NSMenuItem(title: "Paste", action: #selector(BrowserWebView.contextAction_paste(_:)), keyEquivalent: "")
            paste.target = target
            paste.image = pasteIcon
            menu.addItem(paste)

            let selectAll = NSMenuItem(title: "Select All", action: #selector(BrowserWebView.contextAction_selectAll(_:)), keyEquivalent: "")
            selectAll.target = target
            selectAll.image = selectAllIcon
            menu.addItem(selectAll)

            menu.addItem(.separator())
        }

        // --- Selection items (non-editable) ---
        if !hitTest.selectedText.isEmpty && !hitTest.isEditable {
            let copy = NSMenuItem(title: "Copy", action: #selector(BrowserWebView.contextAction_copySelection(_:)), keyEquivalent: "")
            copy.target = target
            copy.image = copyIcon
            copy.representedObject = hitTest.selectedText
            menu.addItem(copy)

            let preview = hitTest.selectedText.count > 20
                ? String(hitTest.selectedText.prefix(20)) + "\u{2026}"
                : hitTest.selectedText
            let search = NSMenuItem(title: "Search Web for \"\(preview)\"",
                                    action: #selector(BrowserWebView.contextAction_searchWebFor(_:)),
                                    keyEquivalent: "")
            search.target = target
            search.image = searchIcon
            search.representedObject = hitTest.selectedText
            menu.addItem(search)

            menu.addItem(.separator())
        }

        // --- Navigation items (always present) ---
        let back = NSMenuItem(title: "Back", action: #selector(BrowserWebView.contextAction_goBack(_:)), keyEquivalent: "")
        back.target = target
        back.image = backIcon
        menu.addItem(back)

        let forward = NSMenuItem(title: "Forward", action: #selector(BrowserWebView.contextAction_goForward(_:)), keyEquivalent: "")
        forward.target = target
        forward.image = forwardIcon
        menu.addItem(forward)

        let reload = NSMenuItem(title: "Reload", action: #selector(BrowserWebView.contextAction_reload(_:)), keyEquivalent: "")
        reload.target = target
        reload.image = reloadIcon
        menu.addItem(reload)

        return menu
    }
}
