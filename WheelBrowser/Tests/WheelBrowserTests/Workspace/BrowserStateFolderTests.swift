import Testing
import Foundation
@testable import WheelBrowser

@Suite("BrowserState Folder Tests")
@MainActor
struct BrowserStateFolderTests {
    @Test("Folders persist membership, active folder, and last active tab across workspace switches")
    func persistsFoldersAcrossWorkspaceSwitches() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstWorkspaceID = try #require(manager.currentWorkspaceID)
        browserState.bindToWorkspace(firstWorkspaceID)

        let looseTabID = try #require(browserState.activeTabId)
        browserState.addTab()
        let folderTabID = try #require(browserState.activeTabId)

        let folderID = browserState.createFolder(
            name: "Research",
            color: "#FF9500",
            movingTabIDs: [folderTabID]
        )

        browserState.selectFolder(nil)
        browserState.selectTab(looseTabID)
        browserState.selectFolder(folderID)

        let secondWorkspaceID = manager.createWorkspace(name: "Second").id
        browserState.bindToWorkspace(secondWorkspaceID)
        browserState.bindToWorkspace(firstWorkspaceID)

        let restoredFolder = try #require(browserState.folder(for: folderID))
        #expect(restoredFolder.name == "Research")
        #expect(restoredFolder.tabIDs == [folderTabID])
        #expect(restoredFolder.lastActiveTabID == folderTabID)
        #expect(browserState.activeFolderId == folderID)
        #expect(browserState.activeTabId == folderTabID)
        #expect(browserState.tab(for: folderTabID)?.folderID == folderID)
        #expect(browserState.tab(for: looseTabID)?.folderID == nil)
    }

    @Test("Reopen closed tab restores folder membership")
    func reopenClosedTabRestoresFolderMembership() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        browserState.bindToWorkspace(try #require(manager.currentWorkspaceID))
        let looseTabID = try #require(browserState.activeTabId)
        browserState.addTab()
        let folderTabID = try #require(browserState.activeTabId)

        let folderID = browserState.createFolder(
            name: "Pinned",
            color: "#34C759",
            movingTabIDs: [folderTabID]
        )

        browserState.selectFolder(folderID)
        browserState.closeTab(folderTabID)
        #expect(browserState.activeTabId == looseTabID)
        #expect(browserState.visibleTabs.map(\.id) == [looseTabID])

        #expect(browserState.reopenLastClosedTab() == true)

        let reopenedTab = try #require(browserState.activeTab)
        #expect(reopenedTab.folderID == folderID)
        #expect(browserState.activeFolderId == folderID)
        #expect(browserState.visibleTabs.map(\.id) == [looseTabID, reopenedTab.id])
    }

    @Test("New foreground and background tabs inherit the active folder")
    func newTabsInheritActiveFolder() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        browserState.bindToWorkspace(try #require(manager.currentWorkspaceID))
        let folderID = browserState.createFolder(name: "Inbox", color: "#5856D6")

        browserState.addTab()
        let foregroundTab = try #require(browserState.activeTab)

        browserState.addTab(withURL: try #require(URL(string: "https://example.com")), activate: false)
        let backgroundTab = try #require(browserState.tabs.last)

        #expect(browserState.activeFolderId == folderID)
        #expect(foregroundTab.folderID == folderID)
        #expect(backgroundTab.folderID == folderID)
    }

    @Test("Range and additive selection follow the global strip order")
    func selectionSemanticsFollowGlobalStripOrder() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        browserState.bindToWorkspace(try #require(manager.currentWorkspaceID))
        let looseTabID = try #require(browserState.activeTabId)

        browserState.addTab()
        let firstFolderTabID = try #require(browserState.activeTabId)
        browserState.addTab()
        let secondFolderTabID = try #require(browserState.activeTabId)
        browserState.addTab()
        let thirdFolderTabID = try #require(browserState.activeTabId)

        let folderID = browserState.createFolder(
            name: "Batch",
            color: "#AF52DE",
            movingTabIDs: [firstFolderTabID, secondFolderTabID, thirdFolderTabID]
        )

        browserState.selectFolder(folderID)
        browserState.handleTabActivation(firstFolderTabID, selectionMode: .replace)
        browserState.handleTabActivation(thirdFolderTabID, selectionMode: .range)

        #expect(browserState.selectedTabIDs == Set([firstFolderTabID, secondFolderTabID, thirdFolderTabID]))
        #expect(!browserState.selectedTabIDs.contains(looseTabID))

        browserState.handleTabActivation(secondFolderTabID, selectionMode: .add)

        #expect(browserState.selectedTabIDs == Set([firstFolderTabID, thirdFolderTabID]))
        #expect(browserState.activeFolderId == folderID)
        #expect(browserState.visibleTabs.map(\.id) == [looseTabID, firstFolderTabID, secondFolderTabID, thirdFolderTabID])
    }

    @Test("Deleting a folder moves its tabs to Loose and keeps a valid active tab")
    func deletingFolderMovesTabsToLoose() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        browserState.bindToWorkspace(try #require(manager.currentWorkspaceID))
        browserState.addTab()
        let movedTabID = try #require(browserState.activeTabId)

        let folderID = browserState.createFolder(
            name: "Read Later",
            color: "#FF3B30",
            movingTabIDs: [movedTabID]
        )

        browserState.deleteFolder(folderID)

        #expect(browserState.folders.isEmpty)
        #expect(browserState.activeFolderId == nil)
        #expect(browserState.activeTabId == movedTabID)
        #expect(browserState.tab(for: movedTabID)?.folderID == nil)
        #expect(browserState.visibleTabs.contains(where: { $0.id == movedTabID }))
    }

    @Test("Keyboard tab switching follows the global strip order")
    func keyboardNavigationFollowsGlobalStripOrder() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        browserState.bindToWorkspace(try #require(manager.currentWorkspaceID))
        let looseTabID = try #require(browserState.activeTabId)

        browserState.addTab()
        let firstFolderTabID = try #require(browserState.activeTabId)
        browserState.addTab()
        let secondFolderTabID = try #require(browserState.activeTabId)

        let folderID = browserState.createFolder(
            name: "Scoped",
            color: "#00C7BE",
            movingTabIDs: [firstFolderTabID, secondFolderTabID]
        )

        browserState.selectFolder(folderID)
        browserState.selectTab(atIndex: 1)
        #expect(browserState.activeTabId == looseTabID)

        browserState.selectNextTab()
        #expect(browserState.activeTabId == firstFolderTabID)

        browserState.selectNextTab()
        #expect(browserState.activeTabId == secondFolderTabID)

        browserState.selectPreviousTab()
        #expect(browserState.activeTabId == firstFolderTabID)
        #expect(browserState.activeFolderId == folderID)
    }

    @Test("Creating an empty folder keeps the current tab visible and active")
    func creatingEmptyFolderKeepsCurrentTabActive() throws {
        let (browserState, manager, directory) = makeBrowserState()
        defer { try? FileManager.default.removeItem(at: directory) }

        browserState.bindToWorkspace(try #require(manager.currentWorkspaceID))
        let originalTabID = try #require(browserState.activeTabId)

        let folderID = browserState.createFolder(name: "Later", color: "#FFCC00")

        #expect(browserState.activeFolderId == folderID)
        #expect(browserState.activeTabId == originalTabID)
        #expect(browserState.visibleTabs.map(\.id) == [originalTabID])
        #expect(browserState.folder(for: folderID)?.tabIDs.isEmpty == true)
    }

    private func makeBrowserState() -> (BrowserState, WorkspaceManager, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let manager = WorkspaceManager(
            workspacesFileURL: directory.appendingPathComponent("workspaces.json"),
            tabStatesFileURL: directory.appendingPathComponent("workspace_tabs.json")
        )

        let browserState = BrowserState(
            workspaceStateStore: WorkspaceStateStore(
                saveTabState: { state, workspaceID in
                    manager.saveTabState(state, for: workspaceID)
                },
                getTabState: { workspaceID in
                    manager.getTabState(for: workspaceID)
                },
                clearTabState: { workspaceID in
                    manager.clearTabState(for: workspaceID)
                }
            )
        )

        return (browserState, manager, directory)
    }
}
