import SwiftUI

// MARK: - Browser Content Area (extracted to help compiler with type checking)

private struct BrowserContentArea: View {
    var activeTab: Tab
    var agentManager: AgentManager
    var browserState: BrowserState
    var noteStore: NoteStore
    @ObservedObject var settings: AppSettings
    var agentEngine: AgentEngine
    var wheelState: TabWheelState
    var noteWindowState: NoteWindowState
    var contextMenuState = ContextMenuState.shared
    let contentExtractor: ContentExtractor

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area - full width
                ZStack(alignment: .bottom) {
                    // Web content - render ALL tabs to keep webviews in hierarchy
                    // This is critical for agent automation on background tabs
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
                    OmniBar(
                        tab: activeTab,
                        agentManager: agentManager,
                        browserState: browserState,
                        agentEngine: agentEngine,
                        contentExtractor: contentExtractor
                    )
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

                // Custom context menu overlay
                ContextMenuOverlay(
                    state: contextMenuState,
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

                NoteWindowContainer(
                    noteStore: noteStore,
                    noteWindowState: noteWindowState,
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
                if tab.url == nil && tab.isChatTab {
                    FullPageChatView(agentManager: agentManager)
                } else if tab.url == nil {
                    WidgetDashboardPageView { url in
                        browserState.addTab(withURL: url)
                    }
                } else {
                    WebViewRepresentable(tab: tab, isActive: isActive)
                        .id(tab.webViewRevision)
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

            if tab.hasActiveAgent {
                AgentControlledTabOverlay(progress: tab.agentProgress)
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
                if let url = notification.object as? URL,
                   state.activeTab?.isChatTab != true {
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

struct ContentView: View {
    @State private var state: BrowserState
    @State private var agentEngine: AgentEngine
    private var agentManager = AgentManager.shared
    private var agentStudioManager = AgentStudioManager.shared
    private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var settings = AppSettings.shared
    private var downloadManager = DownloadManager.shared
    @State private var wheelState = TabWheelState.shared
    @State private var noteStore = NoteStore()
    @State private var noteWindowState = NoteWindowState()
    private let contentExtractor = ContentExtractor()

    init() {
        let browserState = BrowserState()
        let engine = AgentEngine(browserState: browserState, settings: AppSettings.shared)

        _state = State(wrappedValue: browserState)
        _agentEngine = State(wrappedValue: engine)

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
        ZStack {
            VStack(spacing: 0) {
                if let activeTab = state.activeTab {
                    BrowserContentArea(
                        activeTab: activeTab,
                        agentManager: agentManager,
                        browserState: state,
                        noteStore: noteStore,
                        settings: settings,
                        agentEngine: agentEngine,
                        wheelState: wheelState,
                        noteWindowState: noteWindowState,
                        contentExtractor: contentExtractor
                    )
                }
            }
            .frame(minWidth: 400)

            StageManagerStrip(
                browserState: state,
                screenshotManager: TabScreenshotManager.shared
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            NotesStrip(
                noteStore: noteStore,
                onOpenNote: openNote,
                onOpenToday: openTodayNoteFromCurrentPage,
                onCreateNote: createNoteFromCurrentPage
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .overlay {
            if state.activeTab?.hasActiveAgent == true {
                AgentControlledWindowGlow()
            }
        }
        .background(WindowAccessor())
    }

    // MARK: - Body

    var body: some View {
        mainContent
            .frame(minWidth: 800, minHeight: 600)
            .onAppear(perform: handleOnAppear)
            .modifier(TabNotificationModifier(
                state: state
            ))
            .modifier(NavigationNotificationModifier(state: state))
            .modifier(ZoomNotificationModifier(state: state))
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDidChange)) { notification in
                if let workspaceId = notification.userInfo?["newWorkspaceID"] as? UUID {
                    Task { @MainActor in
                        state.bindToWorkspace(workspaceId)
                        noteStore.bindToWorkspace(workspaceId)
                        noteWindowState.close()
                    }
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
            .onReceive(NotificationCenter.default.publisher(for: .openTodayNote)) { _ in
                openTodayNoteFromCurrentPage()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newNoteFromPage)) { _ in
                createNoteFromCurrentPage()
            }
    }

    // MARK: - Handlers

    private func handleOnAppear() {
        if let currentWorkspaceId = workspaceManager.currentWorkspaceID {
            Task { @MainActor in
                state.bindToWorkspace(currentWorkspaceId)
                noteStore.bindToWorkspace(currentWorkspaceId)
            }
        }
    }

    @MainActor
    private func openTodayNoteFromCurrentPage() {
        guard let workspaceID = workspaceManager.currentWorkspaceID else { return }
        noteStore.bindToWorkspace(workspaceID)

        let note = noteStore.ensureDailyNote()
        if let source = currentPageSource() {
            noteStore.insertPageSource(id: note.id, source: source)
        }
        openNote(noteStore.note(with: note.id) ?? note)
    }

    @MainActor
    private func createNoteFromCurrentPage() {
        guard let workspaceID = workspaceManager.currentWorkspaceID else { return }
        noteStore.bindToWorkspace(workspaceID)

        let proposedTitle = currentPageSource()?.title ?? "Untitled Note"
        let note = noteStore.createAdHocNote(title: proposedTitle)
        if let source = currentPageSource() {
            noteStore.insertPageSource(id: note.id, source: source)
        }
        openNote(noteStore.note(with: note.id) ?? note)
    }

    @MainActor
    private func openNote(_ note: NoteRecord) {
        noteWindowState.open(note: note)
    }

    private func currentPageSource() -> NotePageSource? {
        guard let tab = state.activeTab,
              let url = tab.url else {
            return nil
        }

        return NotePageSource(
            title: tab.displayTitle,
            url: url.absoluteString
        )
    }
}

// WindowAccessor, TrafficLightPillManager, TrafficLightPillView, and FocusableView
// are defined in WindowAccessor.swift
