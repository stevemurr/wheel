import Testing
import Foundation
@testable import WheelBrowser

@Suite("WorkspaceManager Tests")
@MainActor
struct WorkspaceManagerTests {

    // Note: These tests would ideally use a testable version of WorkspaceManager
    // that doesn't persist to disk. The structure below shows expected behavior.

    // MARK: - Testable Workspace Manager

    /// A testable version of WorkspaceManager that doesn't persist to disk
    class TestableWorkspaceManager {
        var workspaces: [Workspace] = []
        var currentWorkspaceID: UUID?
        var workspaceTabStates: [UUID: [UUID]] = [:] // Simplified for testing

        init() {
            // Create default workspace
            let defaultWorkspace = Workspace(name: "Default", icon: "house", color: "#007AFF")
            workspaces = [defaultWorkspace]
            currentWorkspaceID = defaultWorkspace.id
        }

        @discardableResult
        func createWorkspace(
            name: String,
            icon: String = "folder",
            color: String = "#007AFF"
        ) -> Workspace {
            let workspace = Workspace(name: name, icon: icon, color: color)
            workspaces.append(workspace)

            if workspaces.count == 1 {
                currentWorkspaceID = workspace.id
            }

            return workspace
        }

        func deleteWorkspace(_ id: UUID) {
            workspaces.removeAll { $0.id == id }

            if currentWorkspaceID == id {
                currentWorkspaceID = workspaces.first?.id
            }
        }

        func switchToWorkspace(_ id: UUID) {
            guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
            currentWorkspaceID = id
            workspaces[index].lastAccessedAt = Date()
        }

        func getCurrentWorkspace() -> Workspace? {
            guard let id = currentWorkspaceID else { return nil }
            return workspaces.first { $0.id == id }
        }

        func updateWorkspace(_ workspace: Workspace) {
            guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
            workspaces[index] = workspace
        }

        func addTabToCurrentWorkspace(_ tabID: UUID) {
            guard let id = currentWorkspaceID,
                  let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

            if !workspaces[index].tabIDs.contains(tabID) {
                workspaces[index].tabIDs.append(tabID)
            }
        }

        func removeTabFromWorkspace(_ tabID: UUID, workspaceID: UUID) {
            guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
            workspaces[index].tabIDs.removeAll { $0 == tabID }
        }

        func tabCount(for workspaceID: UUID) -> Int {
            workspaces.first { $0.id == workspaceID }?.tabIDs.count ?? 0
        }
    }

    // MARK: - Create Workspace Tests

    @Test("Creates workspace with given parameters")
    func createsWorkspaceWithParameters() {
        let manager = TestableWorkspaceManager()
        let initialCount = manager.workspaces.count

        let workspace = manager.createWorkspace(
            name: "Work",
            icon: "briefcase",
            color: "#FF5733"
        )

        #expect(manager.workspaces.count == initialCount + 1)
        #expect(workspace.name == "Work")
        #expect(workspace.icon == "briefcase")
        #expect(workspace.color == "#FF5733")
    }

    @Test("First workspace becomes current")
    func firstWorkspaceBecomeCurrent() {
        let manager = TestableWorkspaceManager()
        manager.workspaces.removeAll()
        manager.currentWorkspaceID = nil

        let workspace = manager.createWorkspace(name: "First")

        #expect(manager.currentWorkspaceID == workspace.id)
    }

    // MARK: - Delete Workspace Tests

    @Test("Deletes workspace by ID")
    func deletesWorkspaceByID() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "ToDelete")
        let countBefore = manager.workspaces.count

        manager.deleteWorkspace(workspace.id)

        #expect(manager.workspaces.count == countBefore - 1)
        #expect(!manager.workspaces.contains { $0.id == workspace.id })
    }

    @Test("Deleting current workspace switches to first available")
    func deletingCurrentSwitchesToFirst() {
        let manager = TestableWorkspaceManager()
        _ = manager.createWorkspace(name: "First")
        let workspace2 = manager.createWorkspace(name: "Second")

        manager.switchToWorkspace(workspace2.id)
        #expect(manager.currentWorkspaceID == workspace2.id)

        manager.deleteWorkspace(workspace2.id)

        // Should switch to first available (either default or workspace1)
        #expect(manager.currentWorkspaceID != workspace2.id)
        #expect(manager.currentWorkspaceID != nil)
    }

    // MARK: - Switch Workspace Tests

    @Test("Switches to workspace by ID")
    func switchesToWorkspaceByID() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Target")

        manager.switchToWorkspace(workspace.id)

        #expect(manager.currentWorkspaceID == workspace.id)
    }

    @Test("Switching updates lastAccessedAt")
    func switchingUpdatesLastAccessedAt() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Target")
        let originalTime = workspace.lastAccessedAt

        // Wait a tiny bit to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)

        manager.switchToWorkspace(workspace.id)

        let updatedWorkspace = manager.workspaces.first { $0.id == workspace.id }
        #expect(updatedWorkspace?.lastAccessedAt != nil)
        #expect(updatedWorkspace!.lastAccessedAt >= originalTime)
    }

    @Test("Switching to non-existent workspace does nothing")
    func switchingToNonExistentDoesNothing() {
        let manager = TestableWorkspaceManager()
        let originalCurrent = manager.currentWorkspaceID

        manager.switchToWorkspace(UUID())

        #expect(manager.currentWorkspaceID == originalCurrent)
    }

    // MARK: - Get Current Workspace Tests

    @Test("Gets current workspace when one is selected")
    func getsCurrentWorkspace() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Current")
        manager.switchToWorkspace(workspace.id)

        let current = manager.getCurrentWorkspace()

        #expect(current?.id == workspace.id)
    }

    @Test("Returns nil when no current workspace")
    func returnsNilWhenNoCurrent() {
        let manager = TestableWorkspaceManager()
        manager.workspaces.removeAll()
        manager.currentWorkspaceID = nil

        let current = manager.getCurrentWorkspace()

        #expect(current == nil)
    }

    // MARK: - Update Workspace Tests

    @Test("Updates existing workspace")
    func updatesExistingWorkspace() {
        let manager = TestableWorkspaceManager()
        var workspace = manager.createWorkspace(name: "Original")

        workspace.name = "Updated"
        manager.updateWorkspace(workspace)

        let updated = manager.workspaces.first { $0.id == workspace.id }
        #expect(updated?.name == "Updated")
    }

    @Test("Update non-existent workspace does nothing")
    func updateNonExistentDoesNothing() {
        let manager = TestableWorkspaceManager()
        let countBefore = manager.workspaces.count

        let nonExistent = Workspace(name: "NonExistent")
        manager.updateWorkspace(nonExistent)

        #expect(manager.workspaces.count == countBefore)
    }

    // MARK: - Tab Management Tests

    @Test("Adds tab to current workspace")
    func addsTabToCurrentWorkspace() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Test")
        manager.switchToWorkspace(workspace.id)

        let tabID = UUID()
        manager.addTabToCurrentWorkspace(tabID)

        let updated = manager.workspaces.first { $0.id == workspace.id }
        #expect(updated?.tabIDs.contains(tabID) == true)
    }

    @Test("Does not add duplicate tab")
    func doesNotAddDuplicateTab() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Test")
        manager.switchToWorkspace(workspace.id)

        let tabID = UUID()
        manager.addTabToCurrentWorkspace(tabID)
        manager.addTabToCurrentWorkspace(tabID)

        let updated = manager.workspaces.first { $0.id == workspace.id }
        #expect(updated?.tabIDs.filter { $0 == tabID }.count == 1)
    }

    @Test("Removes tab from workspace")
    func removesTabFromWorkspace() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Test")
        manager.switchToWorkspace(workspace.id)

        let tabID = UUID()
        manager.addTabToCurrentWorkspace(tabID)
        manager.removeTabFromWorkspace(tabID, workspaceID: workspace.id)

        let updated = manager.workspaces.first { $0.id == workspace.id }
        #expect(updated?.tabIDs.contains(tabID) == false)
    }

    // MARK: - Tab Count Tests

    @Test("Returns correct tab count")
    func returnsCorrectTabCount() {
        let manager = TestableWorkspaceManager()
        let workspace = manager.createWorkspace(name: "Test")
        manager.switchToWorkspace(workspace.id)

        manager.addTabToCurrentWorkspace(UUID())
        manager.addTabToCurrentWorkspace(UUID())
        manager.addTabToCurrentWorkspace(UUID())

        #expect(manager.tabCount(for: workspace.id) == 3)
    }

    @Test("Returns 0 for non-existent workspace")
    func returnsZeroForNonExistent() {
        let manager = TestableWorkspaceManager()

        #expect(manager.tabCount(for: UUID()) == 0)
    }
}

@Suite("Workspace Integration Tests")
@MainActor
struct WorkspaceIntegrationTests {
    @Test("BrowserState restores persisted tab IDs and active tab")
    func restoresPersistedTabsAndSelection() {
        let (manager, directory) = makeWorkspaceManager()
        defer { try? FileManager.default.removeItem(at: directory) }
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

        let firstWorkspaceID = manager.currentWorkspaceID!
        browserState.bindToWorkspace(firstWorkspaceID)
        browserState.addTab()

        let expectedTabIDs = browserState.tabs.map(\.id)
        let expectedActiveTabID = browserState.activeTabId

        let secondWorkspaceID = manager.createWorkspace(name: "Second").id
        browserState.bindToWorkspace(secondWorkspaceID)
        browserState.bindToWorkspace(firstWorkspaceID)

        #expect(browserState.tabs.map(\.id) == expectedTabIDs)
        #expect(browserState.activeTabId == expectedActiveTabID)
        #expect(browserState.activeTab != nil)
    }

    @Test("BrowserState restores background tabs without eagerly creating web views")
    func restoresBackgroundTabsLazily() throws {
        let (manager, directory) = makeWorkspaceManager()
        defer { try? FileManager.default.removeItem(at: directory) }

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

        let workspaceID = manager.currentWorkspaceID!
        let activeID = UUID()
        let backgroundID = UUID()

        manager.saveTabState(
            WorkspaceTabState(
                tabData: [
                    PersistedTab(
                        id: activeID,
                        url: "https://example.com/active",
                        title: "Active",
                        isChatTab: false,
                        hasConversationStarted: false,
                        conversationId: UUID()
                    ),
                    PersistedTab(
                        id: backgroundID,
                        url: "https://example.com/background",
                        title: "Background",
                        isChatTab: false,
                        hasConversationStarted: false,
                        conversationId: UUID()
                    )
                ],
                activeTabId: activeID
            ),
            for: workspaceID
        )

        browserState.bindToWorkspace(workspaceID)

        let activeTab = try #require(browserState.tab(for: activeID))
        let backgroundTab = try #require(browserState.tab(for: backgroundID))

        #expect(activeTab.hasWebView)
        #expect(backgroundTab.hasWebView == false)
        #expect(backgroundTab.url?.absoluteString == "https://example.com/background")
    }

    @Test("Workspace tab count reflects saved tab state")
    func tabCountUsesSavedState() {
        let (manager, directory) = makeWorkspaceManager()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspaceID = manager.currentWorkspaceID!

        let state = WorkspaceTabState(
            tabData: [
                PersistedTab(id: UUID(), url: nil, title: "One", isChatTab: false, hasConversationStarted: false, conversationId: UUID()),
                PersistedTab(id: UUID(), url: nil, title: "Two", isChatTab: false, hasConversationStarted: false, conversationId: UUID())
            ],
            activeTabId: nil
        )

        manager.saveTabState(state, for: workspaceID)

        #expect(manager.tabCount(for: workspaceID) == 2)
    }

    private func makeWorkspaceManager() -> (WorkspaceManager, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return (
            WorkspaceManager(
                workspacesFileURL: directory.appendingPathComponent("workspaces.json"),
                tabStatesFileURL: directory.appendingPathComponent("workspace_tabs.json")
            ),
            directory
        )
    }
}
