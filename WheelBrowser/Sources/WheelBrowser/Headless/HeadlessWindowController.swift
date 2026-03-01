import AppKit
import SwiftUI
import WebKit

/// Creates and manages an off-screen browser window for headless mode.
/// The window is positioned far off-screen but ordered front so WebKit
/// executes JavaScript normally (unlike minimized windows which get throttled).
@MainActor
class HeadlessWindowController {
    private var window: NSWindow?
    private let browserState: BrowserState
    private let agentEngine: AgentEngine

    init() {
        let state = BrowserState()
        let engine = AgentEngine(browserState: state, settings: AppSettings.shared)
        self.browserState = state
        self.agentEngine = engine
    }

    /// Sets up the off-screen window, configures MCP, and optionally navigates to an initial URL.
    func setup() {
        let config = HeadlessConfig.current

        // Create off-screen window with realistic dimensions
        let frame = NSRect(
            x: -10000, y: -10000,
            width: config.windowWidth, height: config.windowHeight
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        // Host a minimal SwiftUI view containing WebViewRepresentable for each tab
        let hostingView = NSHostingView(rootView: HeadlessContentView(browserState: browserState))
        window.contentView = hostingView

        // Order front so WebKit treats this as an active window (JS won't be throttled)
        window.orderFrontRegardless()

        self.window = window

        // Configure and auto-start MCP server
        MCPServer.shared.port = config.port
        MCPServer.shared.configure(browserState: browserState, agentEngine: agentEngine)
        MCPServer.shared.start()

        Log.MCP.info("Headless mode: MCP server starting on port \(config.port)")

        // Navigate to initial URL if provided
        if let urlString = config.initialURL {
            browserState.activeTab?.load(urlString)
            Log.MCP.info("Headless mode: navigating to \(urlString)")
        }
    }
}

/// Minimal SwiftUI view for headless mode — just web views, no UI chrome.
private struct HeadlessContentView: View {
    @ObservedObject var browserState: BrowserState

    var body: some View {
        ZStack {
            ForEach(browserState.tabs) { tab in
                WebViewRepresentable(tab: tab)
                    .opacity(tab.id == browserState.activeTabId ? 1 : 0)
                    .allowsHitTesting(tab.id == browserState.activeTabId)
            }
        }
    }
}
