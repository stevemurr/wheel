import SwiftUI

// MARK: - Browser Content Area (extracted to help compiler with type checking)

private struct BrowserContentArea: View {
    @ObservedObject var activeTab: Tab
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var browserState: BrowserState
    @ObservedObject var settings: AppSettings
    @ObservedObject var agentEngine: AgentEngine
    @ObservedObject var panelState: RightClickPanelState
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
                    panelState.show(at: position)
                })

                // Right-click panel container
                RightClickPanelContainer(
                    state: panelState,
                    browserState: browserState,
                    containerSize: geometry.size
                )

                // Link preview overlay
                LinkPreviewOverlay(containerSize: geometry.size)

                // Overlay windows (Cmd+Click links)
                OverlayWindowContainer(
                    manager: OverlayWindowManager.shared,
                    containerSize: geometry.size
                )
            }
        }
    }
}

/// Container for a single tab's web view - keeps it in hierarchy even when not active
private struct TabWebViewContainer: View {
    @ObservedObject var tab: Tab
    let isActive: Bool

    var body: some View {
        Group {
            if tab.url == nil {
                NewTabPageView()
            } else {
                WebViewRepresentable(tab: tab)
            }
        }
        // Keep inactive tabs in hierarchy but hidden
        // Using opacity instead of removing from hierarchy preserves JS execution
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        // Ensure the view stays the same identity
        .id(tab.id)
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
    @StateObject private var agentEngine: AgentEngine
    @ObservedObject private var agentManager = AgentManager.shared
    @ObservedObject private var agentStudioManager = AgentStudioManager.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var panelState = RightClickPanelState.shared
    private let contentExtractor = ContentExtractor()

    init() {
        let browserState = BrowserState()
        let engine = AgentEngine(browserState: browserState, settings: AppSettings.shared)

        _state = StateObject(wrappedValue: browserState)
        _agentEngine = StateObject(wrappedValue: engine)

        // Configure the shared MCP server with browser dependencies
        Task { @MainActor in
            MCPServer.shared.configure(browserState: browserState, agentEngine: engine)
        }
    }

    // MARK: - Main Content (extracted to help compiler with type checking)

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let activeTab = state.activeTab {
                BrowserContentArea(
                    activeTab: activeTab,
                    agentManager: agentManager,
                    browserState: state,
                    settings: settings,
                    agentEngine: agentEngine,
                    panelState: panelState,
                    contentExtractor: contentExtractor
                )
            }
        }
        .frame(minWidth: 400)
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
                // Extend content into title bar area
                window.styleMask.insert(.fullSizeContentView)
                window.makeKeyAndOrderFront(nil)
                window.acceptsMouseMovedEvents = true

                // Add pill-shaped background behind traffic light buttons
                TrafficLightPillManager.shared.addPill(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Traffic Light Pill Background

/// Manages the pill-shaped background behind the traffic light buttons
final class TrafficLightPillManager {
    static let shared = TrafficLightPillManager()

    private var pillView: TrafficLightPillView?
    private weak var observedWindow: NSWindow?
    private var resizeObserver: NSObjectProtocol?

    private init() {}

    deinit {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // Positioning constants
    private let standardLeftMargin: CGFloat = 18
    private let standardTopOffset: CGFloat = 22
    private let buttonSpacing: CGFloat = 22
    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 4

    func addPill(to window: NSWindow) {
        // Remove any existing pill and observer
        pillView?.removeFromSuperview()
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Get references to the traffic light buttons
        guard let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarView = closeButton.superview else {
            return
        }

        // Create and configure the pill view
        let pill = TrafficLightPillView()
        pill.translatesAutoresizingMaskIntoConstraints = false

        // Insert pill behind the buttons
        titlebarView.addSubview(pill, positioned: .below, relativeTo: closeButton)

        // Set pill size (fixed width based on button layout)
        let pillWidth = buttonSpacing * 2 + zoomButton.frame.width + horizontalPadding * 2
        let pillHeight = closeButton.frame.height + verticalPadding * 2

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor, constant: standardLeftMargin - horizontalPadding),
            pill.widthAnchor.constraint(equalToConstant: pillWidth),
            pill.heightAnchor.constraint(equalToConstant: pillHeight)
        ])

        pillView = pill
        observedWindow = window

        // Position buttons initially
        repositionButtons(in: window)

        // Observe window resize to reposition buttons
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.repositionButtons(in: window)
        }
    }

    private func repositionButtons(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarView = closeButton.superview,
              let pill = pillView else {
            return
        }

        // Reposition traffic light buttons
        let buttonY = titlebarView.bounds.height - standardTopOffset - closeButton.frame.height / 2

        closeButton.setFrameOrigin(NSPoint(x: standardLeftMargin, y: buttonY))
        minimizeButton.setFrameOrigin(NSPoint(x: standardLeftMargin + buttonSpacing, y: buttonY))
        zoomButton.setFrameOrigin(NSPoint(x: standardLeftMargin + buttonSpacing * 2, y: buttonY))

        // Update pill vertical position to match buttons
        pill.frame.origin.y = buttonY - verticalPadding
    }
}

/// The pill-shaped background view behind the traffic light buttons
final class TrafficLightPillView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupAppearance()

        // Observe appearance changes for dark/light mode support
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: NSApplication.didChangeOcclusionStateNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupAppearance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupAppearance() {
        layer?.cornerRadius = bounds.height / 2
        updateColors()
    }

    override func layout() {
        super.layout()
        // Update corner radius when size changes to maintain pill shape
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    @objc private func appearanceDidChange() {
        updateColors()
    }

    private func updateColors() {
        // Use semi-transparent colors that work in both light and dark mode
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDarkMode {
            // Subtle light overlay in dark mode
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        } else {
            // Subtle dark overlay in light mode
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        }
    }
}

class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}
