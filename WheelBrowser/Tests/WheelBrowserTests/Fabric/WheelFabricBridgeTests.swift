import Fabric
import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Wheel browser Fabric provider")
struct WheelFabricBridgeTests {
    @Test("Lists workspace catalog and current workspace resources")
    func listsWorkspaceResources() async throws {
        let workspaceManager = makeWorkspaceManager()
        let addedWorkspace = workspaceManager.createWorkspace(
            name: "Client Work",
            icon: "briefcase",
            color: "#34C759"
        )
        let provider = WheelBrowserFabricProvider(
            browserState: BrowserState(initialWorkspaceId: workspaceManager.currentWorkspaceID),
            contentExtractor: ContentExtractor(),
            workspaceManager: workspaceManager
        )

        let resources = try await provider.listResources(query: nil)
        let workspaceResources = resources.filter { $0.kind == "workspace" }
        let currentWorkspace = try #require(resources.first { $0.kind == "current-workspace" })

        #expect(workspaceResources.count == workspaceManager.workspaces.count)
        #expect(currentWorkspace.metadata["workspaceID"]?.stringValue == workspaceManager.currentWorkspaceID?.uuidString)
        #expect(
            workspaceResources.contains {
                $0.uri.id == addedWorkspace.id.uuidString &&
                    $0.metadata["icon"]?.stringValue == "briefcase" &&
                    $0.metadata["color"]?.stringValue == "#34C759"
            }
        )
    }

    @Test("Resolves workspace resources into workspace context")
    func resolvesWorkspaceContext() async throws {
        let workspaceManager = makeWorkspaceManager()
        let workspace = workspaceManager.getCurrentWorkspace()!
        let provider = WheelBrowserFabricProvider(
            browserState: BrowserState(initialWorkspaceId: workspaceManager.currentWorkspaceID),
            contentExtractor: ContentExtractor(),
            workspaceManager: workspaceManager
        )

        let payload = try await provider.resolveContext(
            for: FabricURI(appID: WheelFabricAppID.browser, kind: "workspace", id: workspace.id.uuidString)
        )

        #expect(payload?.title == workspace.name)
        #expect(payload?.metadata["workspaceID"]?.stringValue == workspace.id.uuidString)
        #expect(payload?.body.contains("Workspace: \(workspace.name)") == true)
    }

    @Test("Emits removal events when workspaces are deleted")
    func emitsWorkspaceRemovalEvents() {
        let workspaceManager = makeWorkspaceManager()
        let removedWorkspace = workspaceManager.createWorkspace(name: "Disposable", icon: "trash", color: "#FF3B30")
        let provider = WheelBrowserFabricProvider(
            browserState: BrowserState(initialWorkspaceId: workspaceManager.currentWorkspaceID),
            contentExtractor: ContentExtractor(),
            workspaceManager: workspaceManager
        )
        let previousWorkspaceIDs = provider.workspaceIDs

        workspaceManager.deleteWorkspace(removedWorkspace.id)
        let events = provider.workspaceCatalogEvents(previousWorkspaceIDs: previousWorkspaceIDs)

        #expect(
            events.contains {
                $0.kind == .resourceRemoved &&
                    $0.resourceKind == "workspace" &&
                    $0.resourceURI?.id == removedWorkspace.id.uuidString
            }
        )
    }

    private func makeWorkspaceManager() -> WorkspaceManager {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return WorkspaceManager(
            workspacesFileURL: directory.appendingPathComponent("workspaces.json"),
            tabStatesFileURL: directory.appendingPathComponent("workspace-tabs.json")
        )
    }
}
