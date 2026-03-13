import Foundation

@MainActor
struct AppContextMenuActionHandler {
    let createFolder: ([UUID]) -> Void
    let moveTabsToFolder: ([UUID], UUID) -> Void
    let removeTabsFromFolders: ([UUID]) -> Void
    let renameFolder: (UUID) -> Void
    let deleteFolder: (UUID) -> Void

    func handle(_ action: ContextMenuAction) -> Bool {
        switch action {
        case .createFolderFromTabs(let tabIDs):
            createFolder(tabIDs)
            return true
        case .moveTabsToFolder(let tabIDs, let folderID):
            moveTabsToFolder(tabIDs, folderID)
            return true
        case .removeTabsFromFolders(let tabIDs):
            removeTabsFromFolders(tabIDs)
            return true
        case .renameFolder(let folderID):
            renameFolder(folderID)
            return true
        case .deleteFolder(let folderID):
            deleteFolder(folderID)
            return true
        default:
            return false
        }
    }
}
