import Foundation

/// An action that can be dispatched from the custom context menu.
enum ContextMenuAction {
    case openLinkInNewTab(url: String)
    case copyLinkAddress(url: String)
    case openImageInNewTab(url: String)
    case saveImageAs(url: String)
    case copyImage(url: String)
    case copyImageAddress(url: String)
    case openMediaInNewTab(url: String, label: String)
    case copyMediaAddress(url: String)
    case copyMediaAtTimestamp(url: String)
    case cut
    case copy
    case paste
    case selectAll
    case copySelection(text: String)
    case searchWebFor(text: String)
    case goBack
    case goForward
    case reload
    case hardReload
    case createFolderFromTabs([UUID])
    case moveTabsToFolder(tabIDs: [UUID], folderID: UUID)
    case removeTabsFromFolders([UUID])
    case renameFolder(UUID)
    case deleteFolder(UUID)
}

/// A single row in the context menu card.
struct ContextMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: ContextMenuAction

    init(title: String, systemImage: String, isEnabled: Bool = true, action: ContextMenuAction) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// A group of context menu items separated by dividers.
struct ContextMenuSection: Identifiable {
    let id = UUID()
    let items: [ContextMenuItem]
}
