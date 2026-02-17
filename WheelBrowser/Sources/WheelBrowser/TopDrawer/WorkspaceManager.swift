import Foundation
import SwiftUI

/// Notification sent when workspace changes - observers can respond to load appropriate tabs
extension Notification.Name {
    static let workspaceDidChange = Notification.Name("workspaceDidChange")
}

/// Manages workspace storage and operations
@MainActor
class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published private(set) var workspaces: [Workspace] = []
    @Published var currentWorkspaceID: UUID?

    /// Cached tab states per workspace for persistence
    @Published private(set) var workspaceTabStates: [UUID: WorkspaceTabState] = [:]

    /// File URL for persisting workspaces
    private var workspacesFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("workspaces.json")
    }

    /// File URL for persisting workspace tab states
    private var tabStatesFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)
        return appDir.appendingPathComponent("workspace_tabs.json")
    }

    private init() {
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

        // If we deleted the current workspace, switch to the first available
        if currentWorkspaceID == id {
            currentWorkspaceID = workspaces.first?.id
        }

        saveWorkspaces()
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
        workspaces.first { $0.id == workspaceID }?.tabIDs.count ?? 0
    }

    // MARK: - Tab State Management

    /// Saves tab state for a workspace
    func saveTabState(_ state: WorkspaceTabState, for workspaceID: UUID) {
        workspaceTabStates[workspaceID] = state
        saveTabStates()
    }

    /// Gets the saved tab state for a workspace
    func getTabState(for workspaceID: UUID) -> WorkspaceTabState? {
        return workspaceTabStates[workspaceID]
    }

    /// Clears tab state for a workspace
    func clearTabState(for workspaceID: UUID) {
        workspaceTabStates.removeValue(forKey: workspaceID)
        saveTabStates()
    }

    // MARK: - Persistence

    private func loadWorkspaces() {
        guard FileManager.default.fileExists(atPath: workspacesFileURL.path) else {
            // Create a default workspace if none exist
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

        do {
            let data = try Data(contentsOf: workspacesFileURL)
            let decoded = try JSONDecoder().decode(WorkspacesData.self, from: data)
            workspaces = decoded.workspaces
            currentWorkspaceID = decoded.currentWorkspaceID
        } catch {
            print("Failed to load workspaces: \(error)")
            // Create a default workspace on error
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
        guard FileManager.default.fileExists(atPath: tabStatesFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: tabStatesFileURL)
            workspaceTabStates = try JSONDecoder().decode([UUID: WorkspaceTabState].self, from: data)
        } catch {
            print("Failed to load tab states: \(error)")
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
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: workspacesFileURL, options: .atomic)
        } catch {
            print("Failed to save workspaces: \(error)")
        }
    }

    private func persistTabStates() async {
        do {
            let encoded = try JSONEncoder().encode(workspaceTabStates)
            try encoded.write(to: tabStatesFileURL, options: .atomic)
        } catch {
            print("Failed to save tab states: \(error)")
        }
    }
}

// MARK: - Persistence Data Structure

private struct WorkspacesData: Codable {
    let workspaces: [Workspace]
    let currentWorkspaceID: UUID?
}
