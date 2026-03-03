import SwiftUI

// MARK: - Browser Content Area (extracted to help compiler with type checking)

private struct BrowserContentArea: View {
    @ObservedObject var activeTab: Tab
    var agentManager: AgentManager
    @ObservedObject var browserState: BrowserState
    @ObservedObject var settings: AppSettings
    var agentEngine: AgentEngine
    @ObservedObject var wheelState: TabWheelState
    let contentExtractor: ContentExtractor
    let isConstellationVisible: Bool

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
                    .opacity(isConstellationVisible ? 0 : 1)
                    .allowsHitTesting(!isConstellationVisible)
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
        }
    }
}

/// Container for a single tab's web view - keeps it in hierarchy even when not active
private struct TabWebViewContainer: View {
    @ObservedObject var tab: Tab
    var agentManager: AgentManager
    let isActive: Bool

    var body: some View {
        ZStack {
            Group {
                if tab.url == nil && tab.isChatTab {
                    FullPageChatView(agentManager: agentManager)
                } else if tab.url == nil {
                    PipelineNewTabPageView()
                } else {
                    WebViewRepresentable(tab: tab)
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
                if let url = notification.object as? URL,
                   state.activeTab?.isChatTab != true {
                    state.activeTab?.load(url.absoluteString)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePictureInPicture)) { _ in
                state.activeTab?.togglePictureInPicture()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDarkMode)) { _ in
                if let tab = state.activeTab {
                    DarkModeManager.shared.toggle(on: tab)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .darkModeChanged)) { _ in
                DarkModeManager.shared.applyToExistingTabs(state.tabs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .darkModeBrightnessChanged)) { _ in
                DarkModeManager.shared.updateBrightnessContrast(on: state.tabs)
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
    @StateObject private var state: BrowserState
    @State private var agentEngine: AgentEngine
    private var agentManager = AgentManager.shared
    @ObservedObject private var agentStudioManager = AgentStudioManager.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var wheelState = TabWheelState.shared
    @ObservedObject private var scrapeManager = ScrapeManager.shared
    @ObservedObject private var constellationState = ConstellationState.shared
    private let contentExtractor = ContentExtractor()

    /// URL to show scrape config sheet for
    @State private var scrapeConfigURL: URL?

    init() {
        let browserState = BrowserState()
        let engine = AgentEngine(browserState: browserState, settings: AppSettings.shared)

        _state = StateObject(wrappedValue: browserState)
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
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                if let activeTab = state.activeTab {
                    BrowserContentArea(
                        activeTab: activeTab,
                        agentManager: agentManager,
                        browserState: state,
                        settings: settings,
                        agentEngine: agentEngine,
                        wheelState: wheelState,
                        contentExtractor: contentExtractor,
                        isConstellationVisible: constellationState.isVisible
                    )
                }
            }
            .frame(minWidth: 400)

            StageManagerStrip(
                browserState: state,
                screenshotManager: TabScreenshotManager.shared
            )
        }
        .background(WindowAccessor())
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
            .onReceive(NotificationCenter.default.publisher(for: .showConstellation)) { _ in
                constellationState.show()
            }
            .overlay {
                if constellationState.isVisible {
                    ConstellationView(
                        state: constellationState,
                        browserState: state
                    )
                    .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrapePage)) { _ in
                if let url = state.activeTab?.url {
                    scrapeConfigURL = url
                }
            }
            .sheet(item: $scrapeConfigURL) { url in
                ScrapeConfigSheet(
                    url: url,
                    onStart: { config in
                        scrapeConfigURL = nil
                        Task {
                            do {
                                try await scrapeManager.startScrape(
                                    url: config.url,
                                    depth: config.depth,
                                    stayOnDomain: config.stayOnDomain,
                                    maxPages: config.maxPages
                                )
                            } catch {
                                Log.Scrape.error("Failed to start scrape", error: error)
                            }
                        }
                    },
                    onCancel: {
                        scrapeConfigURL = nil
                    }
                )
            }
    }

    // MARK: - Handlers

    private func handleOnAppear() {
        if let currentWorkspaceId = workspaceManager.currentWorkspaceID {
            state.bindToWorkspace(currentWorkspaceId)
        }
    }

    private func saveCurrentTabState(to workspaceId: UUID) {
        let persistedTabs = state.tabs.map { tab in
            PersistedTab(
                id: tab.id,
                url: tab.url?.absoluteString,
                title: tab.title,
                isChatTab: tab.isChatTab,
                conversationId: tab.conversationId
            )
        }

        let tabState = WorkspaceTabState(
            tabData: persistedTabs,
            activeTabId: state.activeTabId
        )

        workspaceManager.saveTabState(tabState, for: workspaceId)
    }
}

// WindowAccessor, TrafficLightPillManager, TrafficLightPillView, and FocusableView
// are defined in WindowAccessor.swift
