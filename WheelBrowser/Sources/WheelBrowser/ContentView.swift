import SwiftUI

// MARK: - Browser Content Area (extracted to help compiler with type checking)

private struct BrowserContentArea: View {
    @ObservedObject var tab: Tab
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var browserState: BrowserState
    @ObservedObject var settings: AppSettings
    let contentExtractor: ContentExtractor

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content area
            VStack(spacing: 0) {
                WebViewRepresentable(tab: tab)
                    .id(tab.id)
            }

            // OmniBar at bottom with chat panel above
            OmniBar(
                tab: tab,
                agentManager: agentManager,
                browserState: browserState,
                contentExtractor: contentExtractor
            )
            .zIndex(1000)
        }
    }
}

// MARK: - Notification Handler Modifiers (extracted to help compiler with type checking)

private struct TabNotificationModifier: ViewModifier {
    let state: BrowserState
    let workspaceManager: WorkspaceManager
    let saveTabState: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                state.addTab()
                if let workspaceId = workspaceManager.currentWorkspaceID {
                    saveTabState(workspaceId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                state.closeActiveTab()
                if let workspaceId = workspaceManager.currentWorkspaceID {
                    saveTabState(workspaceId)
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .openURL)) { notification in
                if let url = notification.object as? URL {
                    state.activeTab?.load(url.absoluteString)
                }
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

private struct SidebarNotificationModifier: ViewModifier {
    @ObservedObject var settings: AppSettings

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleTabSidebar)) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    settings.tabSidebarExpanded.toggle()
                }
            }
    }
}

struct ContentView: View {
    @StateObject private var state = BrowserState()
    @ObservedObject private var agentManager = AgentManager.shared
    @ObservedObject private var agentStudioManager = AgentStudioManager.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var settings = AppSettings.shared
    private let contentExtractor = ContentExtractor()

    // MARK: - Main Content (extracted to help compiler with type checking)

    @ViewBuilder
    private var mainContent: some View {
        HStack(spacing: 0) {
            TabSidebar(
                state: state,
                onWorkspaceSelected: { workspaceId in
                    switchToWorkspace(workspaceId)
                }
            )

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 28)
                    .background(WindowAccessor())

                if let tab = state.activeTab {
                    BrowserContentArea(
                        tab: tab,
                        agentManager: agentManager,
                        browserState: state,
                        settings: settings,
                        contentExtractor: contentExtractor
                    )
                }
            }
            .frame(minWidth: 400)
        }
    }

    // MARK: - Body

    var body: some View {
        mainContent
            .frame(minWidth: 800, minHeight: 600)
            .onAppear(perform: handleOnAppear)
            .modifier(TabNotificationModifier(
                state: state,
                workspaceManager: workspaceManager,
                saveTabState: saveCurrentTabState
            ))
            .modifier(NavigationNotificationModifier(state: state))
            .modifier(ZoomNotificationModifier(state: state))
            .modifier(SidebarNotificationModifier(settings: settings))
    }

    // MARK: - Handlers

    private func handleOnAppear() {
        if let currentWorkspaceId = workspaceManager.currentWorkspaceID {
            state.bindToWorkspace(currentWorkspaceId)
        }
    }

    // MARK: - Workspace Switching

    private func switchToWorkspace(_ workspaceId: UUID) {
        // Save current tab state before switching
        if let currentWorkspaceId = state.currentWorkspaceId {
            saveCurrentTabState(to: currentWorkspaceId)
        }

        // Load tabs for the new workspace
        state.loadStateForWorkspace(workspaceId)

        // Switch to workspace's agent if one is assigned
        if let workspace = workspaceManager.workspaces.first(where: { $0.id == workspaceId }),
           let agentId = workspace.defaultAgentID {
            agentStudioManager.setActiveAgent(id: agentId)
        }
    }

    private func saveCurrentTabState(to workspaceId: UUID) {
        let persistedTabs = state.tabs.map { tab in
            PersistedTab(
                id: tab.id,
                url: tab.url?.absoluteString,
                title: tab.title
            )
        }

        let tabState = WorkspaceTabState(
            tabData: persistedTabs,
            activeTabId: state.activeTabId
        )

        workspaceManager.saveTabState(tabState, for: workspaceId)
    }
}

// Allows the window to be dragged from the top area and handles focus
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = FocusableView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isMovableByWindowBackground = true
                window.titlebarAppearsTransparent = true
                window.makeKeyAndOrderFront(nil)
                window.acceptsMouseMovedEvents = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}
