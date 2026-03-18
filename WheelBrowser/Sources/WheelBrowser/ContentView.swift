import SwiftUI

// MARK: - Browser Content Area (extracted to help compiler with type checking)

private struct BrowserContentArea: View {
    var activeTab: Tab?
    var agentManager: AgentManager
    var browserState: BrowserState
    var agentEngine: AgentEngine
    var wheelState: TabWheelState
    var contextMenuState = ContextMenuState.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area - full width
                ZStack(alignment: .bottom) {
                    // Web content - keep instantiated webviews in the hierarchy so
                    // background tabs stay alive, but don't cold-start every restored tab.
                    ZStack {
                        ForEach(browserState.tabs) { tab in
                            TabWebViewContainer(
                                tab: tab,
                                agentManager: agentManager,
                                browserState: browserState,
                                isActive: tab.id == browserState.activeTabId
                            )
                        }
                    }
                    .ignoresSafeArea()

                    // Bottom controls: OmniBar only (uses active tab)
                    if let activeTab {
                        OmniBar(
                            tab: activeTab,
                            agentManager: agentManager,
                            browserState: browserState,
                            agentEngine: agentEngine
                        )
                    }
                }

                // Middle-click interceptor (full overlay, passes through other clicks)
                RightClickInterceptorView(onMiddleClick: { position, size in
                    let initialIndex = browserState.activeTabIndex ?? 0
                    wheelState.show(at: position, initialIndex: initialIndex, tabCount: browserState.tabs.count)
                })

                // Tab wheel container
                RightClickPanelContainer(
                    state: wheelState,
                    browserState: browserState,
                    containerSize: geometry.size
                )

                // Link preview overlay (Shift+Click links)
                LinkPreviewOverlay(containerSize: geometry.size) { url in
                    browserState.addTab(withURL: url)
                }

                // Overlay windows (Cmd+Click links)
                OverlayWindowContainer(
                    manager: OverlayWindowManager.shared,
                    containerSize: geometry.size
                )
            }
            .onAppear {
                // Wire up wheel selection to tab switching
                wheelState.onSelectionChanged = { index in
                    if index < browserState.tabs.count {
                        browserState.selectTab(browserState.tabs[index].id)
                    }
                }
            }
            .onChange(of: browserState.activeTabId) {
                contextMenuState.dismiss()
            }
        }
    }
}

/// Container for a single tab's web view - keeps it in hierarchy even when not active
private struct TabWebViewContainer: View {
    var tab: Tab
    var agentManager: AgentManager
    var browserState: BrowserState
    let isActive: Bool

    var body: some View {
        ZStack {
            Group {
                if tab.url == nil {
                    WidgetDashboardPageView { url in
                        browserState.addTab(withURL: url)
                    }
                } else if tab.hasWebView || isActive {
                    WebViewRepresentable(tab: tab, isActive: isActive)
                        .id(tab.webViewRevision)
                } else {
                    Color.clear
                }
            }

            if let error = tab.lastError {
                NavigationErrorOverlay(error: error) {
                    tab.lastError = nil
                    if let url = tab.url {
                        tab.load(url.absoluteString)
                    }
                }
            }
        }
        // Keep inactive tabs in hierarchy but hidden
        // Using opacity instead of removing from hierarchy preserves JS execution
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
    }
}

/// Overlay shown when a navigation error occurs
private struct NavigationErrorOverlay: View {
    let error: NavigationError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if error.isRetryable {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var title: String {
        let message = error.displayMessage
        return String(message.prefix(while: { $0 != "\n" }))
    }

    private var subtitle: String {
        let message = error.displayMessage
        if let newlineIndex = message.firstIndex(of: "\n") {
            return String(message[message.index(after: newlineIndex)...])
        }
        return ""
    }

    private var iconName: String {
        switch error {
        case .network: return "wifi.exclamationmark"
        case .ssl: return "lock.trianglebadge.exclamationmark"
        case .timeout: return "clock.badge.exclamationmark"
        case .hostNotFound: return "globe.badge.chevron.backward"
        case .resourceNotFound: return "doc.questionmark"
        case .serverError: return "exclamationmark.icloud"
        case .unknown: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Notification Handler Modifiers (extracted to help compiler with type checking)

private struct TabNotificationModifier: ViewModifier {
    let state: BrowserState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                state.addTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                state.closeActiveTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
                if let tabIndex = notification.object as? Int {
                    state.selectTab(atIndex: tabIndex)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousTab)) { _ in
                state.selectPreviousTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
                state.selectNextTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reopenClosedTab)) { _ in
                state.reopenLastClosedTab()
            }
    }
}

private struct NavigationNotificationModifier: ViewModifier {
    let state: BrowserState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .reloadPage)) { _ in
                state.activeTab?.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goBack)) { _ in
                state.activeTab?.goBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goForward)) { _ in
                state.activeTab?.goForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stopLoading)) { _ in
                state.activeTab?.stopLoading()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleReaderMode)) { _ in
                state.activeTab?.toggleReaderMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openURL)) { notification in
                if let url = notification.object as? URL {
                    state.navigate(to: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePictureInPicture)) { _ in
                state.activeTab?.togglePictureInPicture()
            }
    }
}

private struct ZoomNotificationModifier: ViewModifier {
    let state: BrowserState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                state.activeTab?.zoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                state.activeTab?.zoomOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
                state.activeTab?.resetZoom()
            }
    }
}

private struct EmptyFolderSurface: View {
    let folderName: String
    let onCreateTab: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(folderName)
                    .font(.system(size: 24, weight: .semibold))

                Text("This folder has no tabs yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Button(action: onCreateTab) {
                Label("New Tab in Folder", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
    }
}

private struct StartupBrowserSurface: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
        }
        .ignoresSafeArea()
    }
}

private struct FolderEditorRequest: Identifiable {
    let id = UUID()
    let folderIDToEdit: UUID?
    let movingTabIDs: [UUID]
    let title: String
    let submitLabel: String
    let initialName: String
    let initialColor: String
}

struct ContentView: View {
    @State private var state: BrowserState
    @State private var agentEngine: AgentEngine
    private var agentManager = AgentManager.shared
    private var workspaceManager = WorkspaceManager.shared
    private var downloadManager = DownloadManager.shared
    @State private var wheelState = TabWheelState.shared
    @State private var fabricCoordinator: WheelFabricCoordinator?
    @State private var folderEditorRequest: FolderEditorRequest?
    @State private var startupExtensionsReady: Bool
    private var contextMenuState = ContextMenuState.shared
    private let contentExtractor = ContentExtractor()

    init() {
        let browserState = BrowserState(initialWorkspaceId: WorkspaceManager.shared.currentWorkspaceID)
        let engine = AgentEngine(browserState: browserState, settings: AppSettings.shared)
        let startupReady = !AppSettings.shared.extensionsEnabled
            || ExtensionRegistry.shared.hasCompletedInitialRuntimeBootstrap

        _state = State(wrappedValue: browserState)
        _agentEngine = State(wrappedValue: engine)
        _startupExtensionsReady = State(initialValue: startupReady)

        // Configure the shared MCP server with browser dependencies
        // and auto-start if enabled in settings
        Task { @MainActor in
            MCPServer.shared.configure(browserState: browserState, agentEngine: engine)
            if AppSettings.shared.mcpServerEnabled {
                MCPServer.shared.start()
            }
        }
    }

    // MARK: - Main Content (extracted to help compiler with type checking)

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geometry in
            ZStack {
                if startupExtensionsReady {
                    VStack(spacing: 0) {
                        BrowserContentArea(
                            activeTab: state.activeTab,
                            agentManager: agentManager,
                            browserState: state,
                            agentEngine: agentEngine,
                            wheelState: wheelState
                        )
                        .overlay {
                            if state.activeTab == nil {
                                EmptyFolderSurface(folderName: state.activeFolder?.name ?? "Loose") {
                                    state.addTab()
                                }
                            }
                        }
                    }
                    .frame(minWidth: 400)

                    StageManagerStrip(
                        browserState: state,
                        screenshotManager: TabScreenshotManager.shared,
                        onCreateFolder: presentCreateFolder
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ContextMenuOverlay(
                        state: contextMenuState,
                        containerSize: geometry.size,
                        appActionHandler: handleContextMenuAppAction
                    )
                } else {
                    StartupBrowserSurface()
                }
            }
            .background(WindowAccessor())
        }
    }

    // MARK: - Body

    var body: some View {
        mainContent
            .frame(minWidth: 800, minHeight: 600)
            .onAppear(perform: handleOnAppear)
            .onChange(of: state.activeTabId) { _, _ in
                Task { @MainActor in
                    await fabricCoordinator?.publishCurrentPageChange()
                }
            }
            .modifier(TabNotificationModifier(
                state: state
            ))
            .modifier(NavigationNotificationModifier(state: state))
            .modifier(ZoomNotificationModifier(state: state))
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDidChange)) { notification in
                if let workspaceId = notification.userInfo?["newWorkspaceID"] as? UUID {
                    Task { @MainActor in
                        state.bindToWorkspace(workspaceId)
                        await fabricCoordinator?.publishCurrentPageChange()
                        await fabricCoordinator?.publishCurrentWorkspaceChange()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceCatalogDidChange)) { _ in
                Task { @MainActor in
                    await fabricCoordinator?.publishWorkspaceCatalogChange()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDownloads)) { _ in
                downloadManager.togglePanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeAllOverlays)) { _ in
                OverlayWindowManager.shared.closeAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openOverlayInTab)) { notification in
                if let url = notification.object as? URL {
                    state.addTab(withURL: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLinkInNewTab)) { notification in
                if let url = notification.object as? URL {
                    state.addTab(withURL: url, activate: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showTabWheel)) { _ in
                // Show tab wheel at center of window
                let initialIndex = state.activeTabIndex ?? 0
                wheelState.show(at: .zero, initialIndex: initialIndex, tabCount: state.tabs.count)
            }
            .onReceive(NotificationCenter.default.publisher(for: .extensionRuntimeDidUpdate)) { _ in
                state.rebuildAllWebViewsForConfigurationChange()
                OverlayWindowManager.shared.rebuildAllWebViewsForConfigurationChange()
            }
            .sheet(item: $folderEditorRequest) { request in
                FolderEditorSheet(
                    title: request.title,
                    submitLabel: request.submitLabel,
                    initialName: request.initialName,
                    initialColor: request.initialColor
                ) { name, color in
                    if let folderID = request.folderIDToEdit {
                        state.updateFolder(id: folderID, name: name, color: color)
                    } else {
                        _ = state.createFolder(name: name, color: color, movingTabIDs: request.movingTabIDs)
                    }
                }
            }
    }

    // MARK: - Handlers

    private func handleOnAppear() {
        Task { @MainActor in
            await prepareStartupExtensionsIfNeeded()

            if let currentWorkspaceId = workspaceManager.currentWorkspaceID {
                state.bindToWorkspace(currentWorkspaceId)
            }

            if fabricCoordinator == nil {
                let coordinator = WheelFabricCoordinator(
                    browserState: state,
                    contentExtractor: contentExtractor,
                    workspaceManager: workspaceManager
                )
                fabricCoordinator = coordinator
            }

            fabricCoordinator?.start()
            await fabricCoordinator?.publishCurrentPageChange()
            await fabricCoordinator?.publishWorkspaceCatalogChange()
            await fabricCoordinator?.publishCurrentWorkspaceChange()
        }
    }

    @MainActor
    private func handleContextMenuAppAction(_ action: ContextMenuAction) -> Bool {
        contextMenuActionHandler.handle(action)
    }

    @MainActor
    private var contextMenuActionHandler: AppContextMenuActionHandler {
        AppContextMenuActionHandler(
            createFolder: presentCreateFolder,
            moveTabsToFolder: { tabIDs, folderID in
                state.moveTabs(tabIDs, toFolder: folderID)
            },
            removeTabsFromFolders: { tabIDs in
                state.removeTabsFromFolders(tabIDs)
            },
            renameFolder: presentRenameFolder,
            deleteFolder: { folderID in
                state.deleteFolder(folderID)
            }
        )
    }

    @MainActor
    private func prepareStartupExtensionsIfNeeded() async {
        guard !startupExtensionsReady else { return }
        await ExtensionRegistry.shared.bootstrapRuntimeIfNeeded()
        startupExtensionsReady = true
    }

    private func presentCreateFolder(_ movingTabIDs: [UUID]) {
        folderEditorRequest = FolderEditorRequest(
            folderIDToEdit: nil,
            movingTabIDs: movingTabIDs,
            title: movingTabIDs.isEmpty ? "Create Folder" : "New Folder from Selection",
            submitLabel: "Create",
            initialName: TabFolder.defaultName(for: state.folders),
            initialColor: TabFolder.defaultColor(for: state.folders)
        )
    }

    private func presentRenameFolder(_ folderID: UUID) {
        guard let folder = state.folder(for: folderID) else { return }
        folderEditorRequest = FolderEditorRequest(
            folderIDToEdit: folder.id,
            movingTabIDs: [],
            title: "Rename Folder",
            submitLabel: "Save",
            initialName: folder.name,
            initialColor: folder.color
        )
    }
}

// WindowAccessor, TrafficLightPillManager, TrafficLightPillView, and FocusableView
// are defined in WindowAccessor.swift
