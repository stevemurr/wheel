import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained reference to the headless window controller (prevents deallocation).
    private var headlessController: HeadlessWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if HeadlessConfig.current.enabled {
            // Hide from Dock and menu bar in headless mode
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure logging sinks
        Log.addSink(ConsoleSink(minimumLevel: .debug))
        Log.addSink(OSLogSink())

        if HeadlessConfig.current.enabled {
            Log.MCP.info("Starting in headless mode")

            // Close the SwiftUI-created WindowGroup window
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    window.close()
                }
            }

            // Create and set up the headless window controller
            let controller = HeadlessWindowController()
            controller.setup()
            self.headlessController = controller
            return
        }

        // Normal (non-headless) startup
        NSApp.activate(ignoringOtherApps: true)

        // Pre-compile ad blocking rules so they're ready before the first tab opens
        if AppSettings.shared.adBlockingEnabled {
            Task { @MainActor in
                await ContentBlockerManager.shared.compileRules()
            }
        }

        // Log startup configuration
        let settings = AppSettings.shared
        Log.Services.info("LLM endpoint: \(settings.llmEndpoint)")
        Log.Services.info("Summarization model: \(settings.summarizationModel)")
        if settings.summarizationBaseURL == nil {
            Log.Services.warning("Summarization endpoint URL is invalid!")
        }
        Log.LinkPreview.info("Link previews: \(settings.linkPreviewEnabled ? "enabled" : "disabled")")

        // Apply saved appearance mode
        settings.applyAppearance()
        // Set app icon from bundled resource
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SemanticSearchManagerV2.save() is a no-op (DIndex handles persistence server-side).
        // No cleanup needed here.
    }
}

@main
struct WheelBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Tab Sidebar") {
                    NotificationCenter.default.post(name: .toggleTabSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Toggle("Auto-hide Tab Dock", isOn: Binding(
                    get: { AppSettings.shared.tabDockAutoHide },
                    set: { AppSettings.shared.tabDockAutoHide = $0 }
                ))
                .keyboardShortcut("h", modifiers: [.command, .option])

                Divider()

                Button("Focus AI Chat") {
                    NotificationCenter.default.post(name: .focusAISidebar, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Semantic Search") {
                    NotificationCenter.default.post(name: .focusSemanticSearch, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)

                Divider()

                Button("Copy Last Response") {
                    NotificationCenter.default.post(name: .copyLastResponse, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Regenerate Response") {
                    NotificationCenter.default.post(name: .regenerateResponse, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Edit Last Message") {
                    NotificationCenter.default.post(name: .editLastMessage, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

// Navigation commands
            CommandGroup(after: .textEditing) {
                Button("Focus Address Bar") {
                    NotificationCenter.default.post(name: .focusAddressBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Address Bar (Alt)") {
                    NotificationCenter.default.post(name: .focusAddressBar, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("Reload Page") {
                    NotificationCenter.default.post(name: .reloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Stop Loading") {
                    NotificationCenter.default.post(name: .escapePressed, object: nil)
                    NotificationCenter.default.post(name: .stopLoading, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Go Back") {
                    NotificationCenter.default.post(name: .goBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Go Forward") {
                    NotificationCenter.default.post(name: .goForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Find in Page") {
                    NotificationCenter.default.post(name: .findInPage, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // Tab switching commands
            CommandGroup(after: .windowArrangement) {
                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .previousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .nextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Reopen Closed Tab") {
                    NotificationCenter.default.post(name: .reopenClosedTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                // Tab number shortcuts (Cmd+1 through Cmd+9)
                ForEach(1...9, id: \.self) { index in
                    Button("Switch to Tab \(index)") {
                        NotificationCenter.default.post(name: .switchToTab, object: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }

            // Zoom commands
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom In (Alt)") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Picture in Picture") {
                    NotificationCenter.default.post(name: .togglePictureInPicture, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Downloads") {
                    NotificationCenter.default.post(name: .toggleDownloads, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Save to Reading List") {
                    NotificationCenter.default.post(name: .toggleSavePage, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Show Reading List") {
                    NotificationCenter.default.post(name: .focusReadingList, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button("Scrape Page...") {
                    NotificationCenter.default.post(name: .scrapePage, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift, .option])

                Divider()

                Button("Toggle Dark Mode") {
                    NotificationCenter.default.post(name: .toggleDarkMode, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Close All Overlays") {
                    NotificationCenter.default.post(name: .closeAllOverlays, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .option])

                Divider()

                Button("Show Tab Wheel") {
                    NotificationCenter.default.post(name: .showTabWheel, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .option])

                Button("Show Constellation") {
                    NotificationCenter.default.post(name: .showConstellation, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let newTab = Notification.Name("newTab")
    static let closeTab = Notification.Name("closeTab")
    static let toggleTabSidebar = Notification.Name("toggleTabSidebar")

    // Navigation
    static let focusAddressBar = Notification.Name("focusAddressBar")
    static let reloadPage = Notification.Name("reloadPage")
    static let goBack = Notification.Name("goBack")
    static let goForward = Notification.Name("goForward")
    static let stopLoading = Notification.Name("stopLoading")
    static let escapePressed = Notification.Name("escapePressed")

    // Tab switching
    static let switchToTab = Notification.Name("switchToTab")
    static let previousTab = Notification.Name("previousTab")
    static let nextTab = Notification.Name("nextTab")
    static let reopenClosedTab = Notification.Name("reopenClosedTab")

    // Find in page
    static let findInPage = Notification.Name("findInPage")

    // AI sidebar
    static let focusAISidebar = Notification.Name("focusAISidebar")
    static let focusChatInput = Notification.Name("focusChatInput")

    // Semantic search
    static let focusSemanticSearch = Notification.Name("focusSemanticSearch")
    static let embeddingSettingsChanged = Notification.Name("embeddingSettingsChanged")

    // Zoom controls
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")

    // Picture in Picture
    static let togglePictureInPicture = Notification.Name("togglePictureInPicture")

    // Downloads
    static let toggleDownloads = Notification.Name("toggleDownloads")

    // Reading list
    static let toggleSavePage = Notification.Name("toggleSavePage")
    static let focusReadingList = Notification.Name("focusReadingList")

    // Overlay windows
    static let closeAllOverlays = Notification.Name("closeAllOverlays")

    // Tab wheel
    static let showTabWheel = Notification.Name("showTabWheel")

    // Open URL in active tab (for agent/MCP)
    static let openURL = Notification.Name("openURL")

    // Scrape page
    static let scrapePage = Notification.Name("scrapePage")

    // Show scrape panel (posted by ScrapeManager when a job starts)
    static let showScrapePanel = Notification.Name("showScrapePanel")

    // Constellation tab canvas
    static let showConstellation = Notification.Name("showConstellation")

    // Open link in new tab (from context menu)
    static let openLinkInNewTab = Notification.Name("openLinkInNewTab")

    // Chat actions
    static let copyLastResponse = Notification.Name("copyLastResponse")
    static let regenerateResponse = Notification.Name("regenerateResponse")
    static let editLastMessage = Notification.Name("editLastMessage")
}
