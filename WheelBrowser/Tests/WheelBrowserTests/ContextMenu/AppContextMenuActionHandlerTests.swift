import Foundation
import Testing
@testable import WheelBrowser

@Suite("AppContextMenuActionHandler")
@MainActor
struct AppContextMenuActionHandlerTests {
    @Test("Routes rename and delete folder actions")
    func routesFolderActions() {
        let folderID = UUID()
        var renamedFolderID: UUID?
        var deletedFolderID: UUID?

        let handler = makeHandler(
            renameFolder: { renamedFolderID = $0 },
            deleteFolder: { deletedFolderID = $0 }
        )

        #expect(handler.handle(.renameFolder(folderID)) == true)
        #expect(handler.handle(.deleteFolder(folderID)) == true)
        #expect(renamedFolderID == folderID)
        #expect(deletedFolderID == folderID)
    }

    @Test("Leaves WebView-native actions unhandled")
    func leavesWebViewActionsUnhandled() {
        let handler = makeHandler()

        #expect(handler.handle(.reload) == false)
        #expect(handler.handle(.goBack) == false)
    }

    private func makeHandler(
        createFolder: @escaping ([UUID]) -> Void = { _ in },
        moveTabsToFolder: @escaping ([UUID], UUID) -> Void = { _, _ in },
        removeTabsFromFolders: @escaping ([UUID]) -> Void = { _ in },
        renameFolder: @escaping (UUID) -> Void = { _ in },
        deleteFolder: @escaping (UUID) -> Void = { _ in }
    ) -> AppContextMenuActionHandler {
        AppContextMenuActionHandler(
            createFolder: createFolder,
            moveTabsToFolder: moveTabsToFolder,
            removeTabsFromFolders: removeTabsFromFolders,
            renameFolder: renameFolder,
            deleteFolder: deleteFolder
        )
    }
}
