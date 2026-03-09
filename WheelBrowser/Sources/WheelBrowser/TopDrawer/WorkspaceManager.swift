import Foundation
import SwiftUI

/// Notification sent when workspace changes - observers can respond to load appropriate tabs
extension Notification.Name {
    static let workspaceDidChange = Notification.Name("workspaceDidChange")
}

/// Manages workspace storage and operations
@MainActor
@Observable
class WorkspaceManager {
    static let shared = WorkspaceManager()
    private static let defaultWorkspacesFileURL =
        FileManager.appSupportDirectory.appendingPathComponent("workspaces.json")
    private static let defaultTabStatesFileURL =
        FileManager.appSupportDirectory.appendingPathComponent("workspace_tabs.json")

    private(set) var workspaces: [Workspace] = []
    var currentWorkspaceID: UUID?

    /// Cached tab states per workspace for persistence
    private(set) var workspaceTabStates: [UUID: WorkspaceTabState] = [:]

    @ObservationIgnored private let workspacesStore: JSONBackedStore<WorkspacesData>
    @ObservationIgnored private let tabStatesStore: JSONBackedStore<[UUID: WorkspaceTabState]>

    init(
        workspacesFileURL: URL? = nil,
        tabStatesFileURL: URL? = nil
    ) {
        let resolvedWorkspacesURL = workspacesFileURL ?? Self.defaultWorkspacesFileURL
        let resolvedTabStatesURL = tabStatesFileURL ?? Self.defaultTabStatesFileURL
        self.workspacesStore = Self.makeStore(fileURL: resolvedWorkspacesURL)
        self.tabStatesStore = Self.makeStore(fileURL: resolvedTabStatesURL)
        loadWorkspaces()
        loadTabStates()

        // Set current workspace to first one if available and none selected
        if currentWorkspaceID == nil, let first = workspaces.first {
            currentWorkspaceID = first.id
        }
    }

    // MARK: - Public Methods

    /// Creates a new workspace with the given parameters
    @discardableResult
    func createWorkspace(
        name: String,
        icon: String = "folder",
        color: String = "#007AFF",
        tabIDs: [UUID] = [],
        defaultAgentID: UUID? = nil
    ) -> Workspace {
        let workspace = Workspace(
            name: name,
            icon: icon,
            color: color,
            tabIDs: tabIDs,
            defaultAgentID: defaultAgentID
        )

        workspaces.append(workspace)
        saveWorkspaces()

        // If this is the first workspace, make it current
        if workspaces.count == 1 {
            currentWorkspaceID = workspace.id
        }

        return workspace
    }

    /// Deletes a workspace by ID
    func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        workspaceTabStates.removeValue(forKey: id)

        // If we deleted the current workspace, switch to the first available
        if currentWorkspaceID == id {
            currentWorkspaceID = workspaces.first?.id
        }

        saveWorkspaces()
        saveTabStates()
    }

    /// Switches to a workspace by ID
    func switchToWorkspace(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

        let previousWorkspaceID = currentWorkspaceID
        currentWorkspaceID = id
        workspaces[index].lastAccessedAt = Date()
        saveWorkspaces()

        // Post notification so observers (like BrowserState) can respond
        NotificationCenter.default.post(
            name: .workspaceDidChange,
            object: nil,
            userInfo: [
                "newWorkspaceID": id,
                "previousWorkspaceID": previousWorkspaceID as Any
            ]
        )
    }

    /// Gets the current workspace if one is selected
    func getCurrentWorkspace() -> Workspace? {
        guard let id = currentWorkspaceID else { return nil }
        return workspaces.first { $0.id == id }
    }

    /// Updates an existing workspace
    func updateWorkspace(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index] = workspace
        saveWorkspaces()
    }

    /// Updates workspace properties by ID
    func updateWorkspace(
        id: UUID,
        name: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        tabIDs: [UUID]? = nil,
        defaultAgentID: UUID?? = nil
    ) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

        if let name = name {
            workspaces[index].name = name
        }
        if let icon = icon {
            workspaces[index].icon = icon
        }
        if let color = color {
            workspaces[index].color = color
        }
        if let tabIDs = tabIDs {
            workspaces[index].tabIDs = tabIDs
        }
        if let defaultAgentID = defaultAgentID {
            workspaces[index].defaultAgentID = defaultAgentID
        }

        saveWorkspaces()
    }

    /// Adds a tab to the current workspace
    func addTabToCurrentWorkspace(_ tabID: UUID) {
        guard let id = currentWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

        if !workspaces[index].tabIDs.contains(tabID) {
            workspaces[index].tabIDs.append(tabID)
            saveWorkspaces()
        }
    }

    /// Removes a tab from a workspace
    func removeTabFromWorkspace(_ tabID: UUID, workspaceID: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }

        workspaces[index].tabIDs.removeAll { $0 == tabID }
        saveWorkspaces()
    }

    /// Removes a tab from all workspaces (e.g., when tab is closed)
    func removeTabFromAllWorkspaces(_ tabID: UUID) {
        for index in workspaces.indices {
            workspaces[index].tabIDs.removeAll { $0 == tabID }
        }
        saveWorkspaces()
    }

    /// Gets the tab count for a workspace
    func tabCount(for workspaceID: UUID) -> Int {
        if let state = workspaceTabStates[workspaceID] {
            return state.tabData.count
        }
        return workspaces.first { $0.id == workspaceID }?.tabIDs.count ?? 0
    }

    // MARK: - Tab State Management

    /// Saves tab state for a workspace
    func saveTabState(_ state: WorkspaceTabState, for workspaceID: UUID) {
        workspaceTabStates[workspaceID] = state
        syncTabIDs(for: workspaceID, tabIDs: state.tabData.map(\.id))
        saveTabStates()
    }

    /// Gets the saved tab state for a workspace
    func getTabState(for workspaceID: UUID) -> WorkspaceTabState? {
        return workspaceTabStates[workspaceID]
    }

    /// Clears tab state for a workspace
    func clearTabState(for workspaceID: UUID) {
        workspaceTabStates.removeValue(forKey: workspaceID)
        syncTabIDs(for: workspaceID, tabIDs: [])
        saveTabStates()
    }

    private func syncTabIDs(for workspaceID: UUID, tabIDs: [UUID]) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[index].tabIDs = tabIDs
        saveWorkspaces()
    }

    // MARK: - Persistence

    private func loadWorkspaces() {
        do {
            guard let decoded = try workspacesStore.load() else {
                let defaultWorkspace = Workspace(
                    name: "Default",
                    icon: "house",
                    color: "#007AFF"
                )
                workspaces = [defaultWorkspace]
                currentWorkspaceID = defaultWorkspace.id
                saveWorkspaces()
                return
            }

            workspaces = decoded.workspaces
            currentWorkspaceID = decoded.currentWorkspaceID
        } catch {
            Log.Workspace.error("Failed to load workspaces: \(error.localizedDescription)")
            // Create a default workspace if none exist
            let defaultWorkspace = Workspace(
                name: "Default",
                icon: "house",
                color: "#007AFF"
            )
            workspaces = [defaultWorkspace]
            currentWorkspaceID = defaultWorkspace.id
        }
    }

    private func loadTabStates() {
        do {
            workspaceTabStates = try tabStatesStore.load() ?? [:]
        } catch {
            Log.Workspace.error("Failed to load tab states: \(error.localizedDescription)")
        }
    }

    private func saveWorkspaces() {
        Task {
            await persistWorkspaces()
        }
    }

    private func saveTabStates() {
        Task {
            await persistTabStates()
        }
    }

    private func persistWorkspaces() async {
        do {
            let data = WorkspacesData(
                workspaces: workspaces,
                currentWorkspaceID: currentWorkspaceID
            )
            try workspacesStore.save(data)
        } catch {
            Log.Workspace.error("Failed to save workspaces: \(error.localizedDescription)")
        }
    }

    private func persistTabStates() async {
        do {
            try tabStatesStore.save(workspaceTabStates)
        } catch {
            Log.Workspace.error("Failed to save tab states: \(error.localizedDescription)")
        }
    }

    private static func makeStore<Value: Codable>(fileURL: URL) -> JSONBackedStore<Value> {
        JSONBackedStore(
            backend: FileSystemStoreBackend(rootURL: fileURL.deletingLastPathComponent()),
            key: StoreKey(fileURL.lastPathComponent)
        )
    }
}

// MARK: - Persistence Data Structure

private struct WorkspacesData: Codable {
    let workspaces: [Workspace]
    let currentWorkspaceID: UUID?
}
