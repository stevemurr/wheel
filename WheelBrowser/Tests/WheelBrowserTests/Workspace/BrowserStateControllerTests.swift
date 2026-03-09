import Foundation
import Testing
@testable import WheelBrowser

@Suite("BrowserState Controllers")
@MainActor
struct BrowserStateControllerTests {
    @Test("Tab collection restores folder membership from workspace snapshots")
    func tabCollectionRestoresFolderMembership() throws {
        var model = BrowserTabModel()
        let controller = TabCollectionController()
        let folderID = UUID()
        let restoredTabID = UUID()
        let looseTabID = UUID()
        let folder = TabFolder(
            id: folderID,
            name: "Saved",
            color: "#007AFF",
            tabIDs: [restoredTabID],
            lastActiveTabID: restoredTabID
        )
        let state = WorkspaceTabState(
            tabData: [
                PersistedTab(
                    id: restoredTabID,
                    url: "https://example.com/restored",
                    title: "Restored",
                    folderID: nil,
                    isChatTab: false,
                    hasConversationStarted: false,
                    conversationId: UUID()
                ),
                PersistedTab(
                    id: looseTabID,
                    url: "https://example.com/loose",
                    title: "Loose",
                    folderID: nil,
                    isChatTab: false,
                    hasConversationStarted: false,
                    conversationId: UUID()
                ),
            ],
            activeTabId: restoredTabID,
            folders: [folder],
            activeFolderId: folderID
        )

        controller.restoreTabs(from: state, in: &model)

        #expect(model.tabs.count == 2)
        #expect(model.tabsByID[restoredTabID]?.folderID == folderID)
        #expect(model.tabsByID[restoredTabID]?.url?.absoluteString == "https://example.com/restored")
        #expect(model.tabsByID[restoredTabID]?.hasWebView == false)
        #expect(model.tabsByID[looseTabID]?.folderID == nil)
        #expect(model.folders.first?.tabIDs == [restoredTabID])
        #expect(model.folders.first?.lastActiveTabID == restoredTabID)
    }

    @Test("Selection controller applies replace, range, and add semantics in strip order")
    func selectionControllerAppliesSelectionModes() {
        var model = BrowserTabModel()
        let collectionController = TabCollectionController()
        let selectionController = TabSelectionController()
        let first = collectionController.appendTab(title: "One", model: &model)
        let second = collectionController.appendTab(title: "Two", model: &model)
        let third = collectionController.appendTab(title: "Three", model: &model)
        var selection = BrowserSelectionModel()

        selectionController.activateTab(
            first.id,
            selectionMode: .replace,
            followTabFolder: false,
            model: model,
            selection: &selection,
            validFolderID: { $0 }
        )
        selectionController.activateTab(
            third.id,
            selectionMode: .range,
            followTabFolder: false,
            model: model,
            selection: &selection,
            validFolderID: { $0 }
        )

        #expect(selection.selectedTabIDs == Set([first.id, second.id, third.id]))

        selectionController.activateTab(
            second.id,
            selectionMode: .add,
            followTabFolder: false,
            model: model,
            selection: &selection,
            validFolderID: { $0 }
        )

        #expect(selection.selectedTabIDs == Set([first.id, third.id]))
        #expect(selection.activeTabId == second.id)
        #expect(selection.tabSelectionAnchorId == second.id)
    }

    @Test("Selection controller resolves the next visible tab after removal")
    func selectionControllerResolvesReplacementTabs() {
        var model = BrowserTabModel()
        let collectionController = TabCollectionController()
        let selectionController = TabSelectionController()
        _ = collectionController.appendTab(title: "One", model: &model)
        let second = collectionController.appendTab(title: "Two", model: &model)
        let third = collectionController.appendTab(title: "Three", model: &model)

        _ = collectionController.removeTab(second.id, from: &model)
        #expect(selectionController.replacementVisibleTabID(afterRemovingAt: 1, model: model) == third.id)

        var lastRemovalModel = BrowserTabModel()
        _ = collectionController.appendTab(title: "One", model: &lastRemovalModel)
        let lastModelSecond = collectionController.appendTab(title: "Two", model: &lastRemovalModel)
        let lastModelThird = collectionController.appendTab(title: "Three", model: &lastRemovalModel)
        _ = collectionController.removeTab(lastModelThird.id, from: &lastRemovalModel)

        #expect(selectionController.replacementVisibleTabID(afterRemovingAt: 2, model: lastRemovalModel) == lastModelSecond.id)
        #expect(selectionController.replacementVisibleTabID(afterRemovingAt: 0, model: BrowserTabModel()) == nil)
    }

    @Test("Workspace session controller binds, saves, loads, and clears state")
    func workspaceSessionControllerRoundTrip() {
        var savedStates: [UUID: WorkspaceTabState] = [:]
        let workspaceID = UUID()
        let nextWorkspaceID = UUID()
        let tabID = UUID()
        var controller = WorkspaceSessionController(
            workspaceStateStore: WorkspaceStateStore(
                saveTabState: { state, workspaceID in
                    savedStates[workspaceID] = state
                },
                getTabState: { workspaceID in
                    savedStates[workspaceID]
                },
                clearTabState: { workspaceID in
                    savedStates.removeValue(forKey: workspaceID)
                }
            )
        )
        let state = WorkspaceTabState(
            tabData: [
                PersistedTab(
                    id: tabID,
                    url: "https://example.com",
                    title: "Example",
                    folderID: nil,
                    isChatTab: false,
                    hasConversationStarted: false,
                    conversationId: UUID()
                ),
            ],
            activeTabId: tabID
        )

        #expect(controller.bind(to: workspaceID) == nil)
        #expect(controller.bind(to: nextWorkspaceID) == workspaceID)

        controller.saveState(state, for: nextWorkspaceID)

        let loaded = controller.loadState(for: nextWorkspaceID)
        #expect(loaded?.activeTabId == tabID)
        #expect(loaded?.tabData.first?.id == tabID)

        controller.clearState(for: nextWorkspaceID)

        #expect(controller.loadState(for: nextWorkspaceID) == nil)
    }
}
