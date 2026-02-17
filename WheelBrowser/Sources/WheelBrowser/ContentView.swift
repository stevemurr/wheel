import SwiftUI

struct ContentView: View {
    @StateObject private var state = BrowserState()
    @ObservedObject private var agentManager = AgentManager.shared
    @ObservedObject private var settings = AppSettings.shared
    private let contentExtractor = ContentExtractor()

    var body: some View {
        HStack(spacing: 0) {
            // Tab Sidebar on the left
            TabSidebar(state: state)

            // Main browser content
            VStack(spacing: 0) {
                // Draggable title bar area
                Color.clear
                    .frame(height: 28)
                    .background(WindowAccessor())

                // Web content with AI overlay
                if let tab = state.activeTab {
                    ZStack(alignment: .trailing) {
                        WebViewRepresentable(tab: tab)
                            .id(tab.id) // Force view refresh on tab change

                        // AI Sidebar overlay on the right (hover to reveal)
                        if settings.sidebarVisible {
                            AISidebarContainer(
                                agentManager: agentManager,
                                tab: tab,
                                contentExtractor: contentExtractor
                            )
                        }
                    }

                    // Navigation bar at the bottom
                    NavigationBar(tab: tab)
                }
            }
            .frame(minWidth: 400)
        }
        .frame(minWidth: 800, minHeight: 600)
        // Tab management
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
            state.addTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            state.closeActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.sidebarVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTabSidebar)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                settings.tabSidebarExpanded.toggle()
            }
        }
        // Navigation actions
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
        // Tab switching
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
        // Zoom controls
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
