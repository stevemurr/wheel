import Fabric
import Foundation

enum WheelFabricAppID {
    static let browser = "wheel.browser"
    static let notes = "wheel.notes"
    static let chat = "wheel.chat"
}

@MainActor
final class WheelBrowserFabricProvider: FabricResourceProvider, FabricSubscriptionProvider {
    let appID = WheelFabricAppID.browser

    private let browserState: BrowserState
    private let contentExtractor: ContentExtractor
    private let workspaceManager: WorkspaceManager

    init(
        browserState: BrowserState,
        contentExtractor: ContentExtractor,
        workspaceManager: WorkspaceManager
    ) {
        self.browserState = browserState
        self.contentExtractor = contentExtractor
        self.workspaceManager = workspaceManager
    }

    var workspaceIDs: Set<UUID> {
        Set(workspaceManager.workspaces.map(\.id))
    }

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        var resources = browserResources()
        resources.append(contentsOf: workspaceResources())
        if let currentWorkspace = currentWorkspaceResource() {
            resources.insert(currentWorkspace, at: min(resources.count, 2))
        }

        guard let query, !query.isEmpty else { return resources }
        let loweredQuery = query.lowercased()

        return resources.filter { resource in
            [
                resource.title,
                resource.summary,
                resource.metadata["url"]?.stringValue ?? "",
                resource.metadata["name"]?.stringValue ?? "",
                resource.metadata["color"]?.stringValue ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(loweredQuery)
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        switch uri.kind {
        case "page":
            guard let activeTab = browserState.activeTab else { return nil }
            return await contextPayload(for: activeTab, kind: "page", resourceURI: uri)

        case "page-snapshot":
            guard let tabID = UUID(uuidString: uri.id),
                  let bridge = browserState.bridge(for: tabID) else {
                return nil
            }

            let snapshot = try await bridge.snapshot()
            return FabricContextPayload(
                uri: uri,
                kind: uri.kind,
                title: snapshot.title,
                body: snapshot.textRepresentation,
                metadata: [
                    "url": .string(snapshot.url),
                    "tabID": .string(uri.id),
                ],
                presentation: .init(
                    systemImage: "camera.viewfinder",
                    tint: "orange",
                    subtitle: snapshot.url,
                    categoryLabel: "Snapshot"
                )
            )

        case "tab":
            guard let tabID = UUID(uuidString: uri.id),
                  let tab = browserState.tab(for: tabID) else {
                return nil
            }
            return await contextPayload(for: tab, kind: "tab", resourceURI: uri)

        case "workspace":
            guard let workspaceID = UUID(uuidString: uri.id),
                  let workspace = workspaceManager.workspaces.first(where: { $0.id == workspaceID }) else {
                return nil
            }
            return workspaceContextPayload(
                for: workspace,
                kind: "workspace",
                resourceURI: uri
            )

        case "current-workspace":
            guard let workspace = workspaceManager.getCurrentWorkspace() else {
                return nil
            }
            return workspaceContextPayload(
                for: workspace,
                kind: "current-workspace",
                resourceURI: uri
            )

        default:
            return nil
        }
    }

    func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let requestedAppID = request.appID, requestedAppID != appID {
            throw FabricError.unsupportedSubscription("Wheel browser provider only supports \(appID)")
        }
    }

    func currentPageEvent() -> FabricEvent? {
        guard let activeTab = browserState.activeTab,
              let url = activeTab.url?.absoluteString else {
            return nil
        }

        return FabricEvent(
            appID: appID,
            kind: .currentPageChanged,
            resourceURI: FabricURI(appID: appID, kind: "page", id: "current"),
            resourceKind: "page",
            payload: [
                "tabID": .string(activeTab.id.uuidString),
                "title": .string(activeTab.displayTitle),
                "url": .string(url),
            ]
        )
    }

    func currentWorkspaceEvent() -> FabricEvent? {
        guard let workspace = workspaceManager.getCurrentWorkspace() else {
            return nil
        }

        return FabricEvent(
            appID: appID,
            kind: .resourceUpdated,
            resourceURI: FabricURI(appID: appID, kind: "current-workspace", id: "current"),
            resourceKind: "current-workspace",
            payload: workspaceMetadata(for: workspace, isCurrent: true)
        )
    }

    func workspaceCatalogEvents(previousWorkspaceIDs: Set<UUID>) -> [FabricEvent] {
        let currentWorkspaces = workspaceManager.workspaces
        let currentWorkspaceIDs = Set(currentWorkspaces.map(\.id))

        var events = currentWorkspaces.map { workspace in
            FabricEvent(
                appID: appID,
                kind: .resourceUpdated,
                resourceURI: FabricURI(appID: appID, kind: "workspace", id: workspace.id.uuidString),
                resourceKind: "workspace",
                payload: workspaceMetadata(
                    for: workspace,
                    isCurrent: workspace.id == workspaceManager.currentWorkspaceID
                )
            )
        }

        for removedWorkspaceID in previousWorkspaceIDs.subtracting(currentWorkspaceIDs) {
            events.append(
                FabricEvent(
                    appID: appID,
                    kind: .resourceRemoved,
                    resourceURI: FabricURI(appID: appID, kind: "workspace", id: removedWorkspaceID.uuidString),
                    resourceKind: "workspace",
                    payload: [
                        "workspaceID": .string(removedWorkspaceID.uuidString),
                    ]
                )
            )
        }

        return events
    }

    private func browserResources() -> [FabricResourceDescriptor] {
        var resources: [FabricResourceDescriptor] = browserState.tabs.compactMap { tab in
            guard let url = tab.url?.absoluteString else { return nil }

            return FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "tab", id: tab.id.uuidString),
                kind: "tab",
                title: tab.displayTitle,
                summary: url,
                capabilities: [.read, .mention],
                metadata: [
                    "url": .string(url),
                    "tabID": .string(tab.id.uuidString),
                ],
                presentation: .init(
                    systemImage: "square.on.square",
                    tint: "blue",
                    subtitle: url,
                    categoryLabel: "Tab"
                )
            )
        }

        if let activeTab = browserState.activeTab,
           let url = activeTab.url?.absoluteString {
            resources.insert(
                FabricResourceDescriptor(
                    uri: FabricURI(appID: appID, kind: "page", id: "current"),
                    kind: "page",
                    title: "Current Page",
                    summary: activeTab.displayTitle,
                    capabilities: [.read, .mention, .subscribe],
                    metadata: [
                        "url": .string(url),
                        "tabID": .string(activeTab.id.uuidString),
                    ],
                    presentation: .init(
                        systemImage: "doc.text",
                        tint: "purple",
                        subtitle: url,
                        categoryLabel: "Current"
                    )
                ),
                at: 0
            )

            resources.insert(
                FabricResourceDescriptor(
                    uri: FabricURI(appID: appID, kind: "page-snapshot", id: activeTab.id.uuidString),
                    kind: "page-snapshot",
                    title: "Page Snapshot",
                    summary: activeTab.displayTitle,
                    capabilities: [.read, .mention, .subscribe, .snapshot],
                    metadata: [
                        "url": .string(url),
                        "tabID": .string(activeTab.id.uuidString),
                    ],
                    presentation: .init(
                        systemImage: "camera.viewfinder",
                        tint: "orange",
                        subtitle: url,
                        categoryLabel: "Snapshot"
                    )
                ),
                at: 1
            )
        }

        return resources
    }

    private func workspaceResources() -> [FabricResourceDescriptor] {
        workspaceManager.workspaces.map { workspace in
            let isCurrent = workspace.id == workspaceManager.currentWorkspaceID
            return FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "workspace", id: workspace.id.uuidString),
                kind: "workspace",
                title: workspace.name,
                summary: isCurrent ? "Current Wheel workspace" : "Wheel workspace",
                capabilities: [.read],
                metadata: workspaceMetadata(for: workspace, isCurrent: isCurrent),
                presentation: .init(
                    systemImage: workspace.icon,
                    tint: "blue",
                    subtitle: isCurrent ? "Current workspace" : workspace.color,
                    categoryLabel: "Workspace"
                )
            )
        }
    }

    private func currentWorkspaceResource() -> FabricResourceDescriptor? {
        guard let workspace = workspaceManager.getCurrentWorkspace() else {
            return nil
        }

        return FabricResourceDescriptor(
            uri: FabricURI(appID: appID, kind: "current-workspace", id: "current"),
            kind: "current-workspace",
            title: workspace.name,
            summary: "Current Wheel workspace",
            capabilities: [.read, .subscribe],
            metadata: workspaceMetadata(for: workspace, isCurrent: true),
            presentation: .init(
                systemImage: workspace.icon,
                tint: "blue",
                subtitle: workspace.color,
                categoryLabel: "Current Workspace"
            )
        )
    }

    private func contextPayload(
        for tab: Tab,
        kind: String,
        resourceURI: FabricURI
    ) async -> FabricContextPayload {
        if tab.hasWebView,
           let extracted = await contentExtractor.extractContent(from: tab) {
            return FabricContextPayload(
                uri: resourceURI,
                kind: kind,
                title: extracted.title,
                body: extracted.textContent,
                metadata: [
                    "url": .string(extracted.url),
                    "tabID": .string(tab.id.uuidString),
                ],
                presentation: presentation(for: kind, url: extracted.url)
            )
        }

        let urlString = tab.url?.absoluteString ?? "about:blank"
        return FabricContextPayload(
            uri: resourceURI,
            kind: kind,
            title: tab.displayTitle,
            body: "Title: \(tab.displayTitle)\nURL: \(urlString)",
            metadata: [
                "url": .string(urlString),
                "tabID": .string(tab.id.uuidString),
            ],
            presentation: presentation(for: kind, url: urlString)
        )
    }

    private func workspaceContextPayload(
        for workspace: Workspace,
        kind: String,
        resourceURI: FabricURI
    ) -> FabricContextPayload {
        let isCurrent = workspace.id == workspaceManager.currentWorkspaceID
        let body = """
        Workspace: \(workspace.name)
        Icon: \(workspace.icon)
        Color: \(workspace.color)
        Tab Count: \(workspace.tabIDs.count)
        Current: \(isCurrent ? "yes" : "no")
        """

        return FabricContextPayload(
            uri: resourceURI,
            kind: kind,
            title: workspace.name,
            body: body,
            metadata: workspaceMetadata(for: workspace, isCurrent: isCurrent),
            presentation: .init(
                systemImage: workspace.icon,
                tint: "blue",
                subtitle: isCurrent ? "Current workspace" : workspace.color,
                categoryLabel: kind == "current-workspace" ? "Current Workspace" : "Workspace"
            )
        )
    }

    private func workspaceMetadata(for workspace: Workspace, isCurrent: Bool) -> FabricMetadata {
        [
            "workspaceID": .string(workspace.id.uuidString),
            "name": .string(workspace.name),
            "icon": .string(workspace.icon),
            "color": .string(workspace.color),
            "isCurrent": .bool(isCurrent),
        ]
    }

    private func presentation(for kind: String, url: String) -> FabricPresentationHints {
        switch kind {
        case "page":
            return .init(
                systemImage: "doc.text",
                tint: "purple",
                subtitle: url,
                categoryLabel: "Current"
            )
        case "page-snapshot":
            return .init(
                systemImage: "camera.viewfinder",
                tint: "orange",
                subtitle: url,
                categoryLabel: "Snapshot"
            )
        default:
            return .init(
                systemImage: "square.on.square",
                tint: "blue",
                subtitle: url,
                categoryLabel: "Tab"
            )
        }
    }
}

@MainActor
final class WheelFabricCoordinator {
    private let browserProvider: WheelBrowserFabricProvider
    private let browserClient: FabricXPCClient
    let consumerClient: FabricXPCClient

    private var isRegistered = false
    private var isRegistering = false
    private var publishedWorkspaceIDs: Set<UUID> = []

    init(
        browserState: BrowserState,
        contentExtractor: ContentExtractor,
        workspaceManager: WorkspaceManager
    ) {
        self.browserProvider = WheelBrowserFabricProvider(
            browserState: browserState,
            contentExtractor: contentExtractor,
            workspaceManager: workspaceManager
        )
        self.browserClient = FabricXPCClient(
            resourceProvider: AnyFabricResourceProvider(browserProvider),
            actionProvider: nil,
            subscriptionProvider: AnyFabricSubscriptionProvider(browserProvider)
        )
        self.consumerClient = FabricXPCClient()
    }

    func start() {
        guard !isRegistered, !isRegistering else { return }
        isRegistering = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isRegistering = false }

            do {
                try await browserClient.register(
                    appID: browserProvider.appID,
                    exposesResources: true,
                    exposesActions: false,
                    exposesSubscriptions: true
                )
                isRegistered = true
                publishedWorkspaceIDs = browserProvider.workspaceIDs
                Log.Services.info("Fabric providers registered")
                await publishCurrentPageChange()
                await publishWorkspaceCatalogChange()
                await publishCurrentWorkspaceChange()
            } catch {
                isRegistered = false
                Log.Services.warning("Fabric registration failed: \(error.localizedDescription)")
            }
        }
    }

    func publishCurrentPageChange() async {
        guard isRegistered,
              let event = browserProvider.currentPageEvent() else {
            return
        }

        do {
            try await browserClient.publish(event: event, from: browserProvider.appID)
        } catch {
            Log.Services.warning("Fabric current-page publish failed: \(error.localizedDescription)")
        }
    }

    func publishWorkspaceCatalogChange() async {
        guard isRegistered else { return }

        let events = browserProvider.workspaceCatalogEvents(previousWorkspaceIDs: publishedWorkspaceIDs)
        publishedWorkspaceIDs = browserProvider.workspaceIDs

        for event in events {
            do {
                try await browserClient.publish(event: event, from: browserProvider.appID)
            } catch {
                Log.Services.warning("Fabric workspace publish failed: \(error.localizedDescription)")
            }
        }
    }

    func publishCurrentWorkspaceChange() async {
        guard isRegistered,
              let event = browserProvider.currentWorkspaceEvent() else {
            return
        }

        do {
            try await browserClient.publish(event: event, from: browserProvider.appID)
        } catch {
            Log.Services.warning("Fabric current-workspace publish failed: \(error.localizedDescription)")
        }
    }
}
