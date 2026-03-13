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

        Task { @MainActor in
            await ExtensionRegistry.shared.bootstrapRuntimeIfNeeded()
            await ContentBlockerManager.shared.refresh(force: false)
            await ExtensionRegistry.shared.reload()
            ContentBlockerManager.shared.startAutomaticRefresh()
        }

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

        // Log startup configuration
        let settings = AppSettings.shared
        Task.detached(priority: .utility) {
            let profile = WheelModelConfigurationProvider.shared.currentProfile()
            let availability = await WheelModelContextService.shared.availabilityStatus()
            if availability.isAvailable {
                Log.Services.info("AI model \(profile.displayName): available")
            } else {
                Log.Services.warning("AI model \(profile.displayName) not available: \(availability.reason ?? "unknown")")
            }
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
        // SemanticSearchManagerV2.save() is a no-op (SQLite WAL handles persistence).
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
                    OmniBarCommandCenter.shared.send(.focusAISidebar)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Semantic Search") {
                    OmniBarCommandCenter.shared.send(.focusSemanticSearch)
                }
                .keyboardShortcut("j", modifiers: .command)

                Divider()

                Button("Copy Last Response") {
                    OmniBarCommandCenter.shared.send(.copyLastResponse)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Regenerate Response") {
                    OmniBarCommandCenter.shared.send(.regenerateResponse)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Edit Last Message") {
                    OmniBarCommandCenter.shared.send(.editLastMessage)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

// Navigation commands
            CommandGroup(after: .textEditing) {
                Button("Focus Address Bar") {
                    OmniBarCommandCenter.shared.send(.focusAddressBar(selectAll: true))
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Address Bar (Alt)") {
                    OmniBarCommandCenter.shared.send(.focusAddressBar(selectAll: true))
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("Reload Page") {
                    NotificationCenter.default.post(name: .reloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Toggle Reader Mode") {
                    NotificationCenter.default.post(name: .toggleReaderMode, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Stop Loading") {
                    OmniBarCommandCenter.shared.send(.escape)
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
                    OmniBarCommandCenter.shared.send(.findInPage)
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
                    OmniBarCommandCenter.shared.send(.toggleSavePage)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Show Reading List") {
                    OmniBarCommandCenter.shared.send(.focusReadingList)
                }
                .keyboardShortcut("b", modifiers: .command)

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
    static let reloadPage = Notification.Name("reloadPage")
    static let toggleReaderMode = Notification.Name("toggleReaderMode")
    static let goBack = Notification.Name("goBack")
    static let goForward = Notification.Name("goForward")
    static let stopLoading = Notification.Name("stopLoading")

    // Tab switching
    static let switchToTab = Notification.Name("switchToTab")
    static let previousTab = Notification.Name("previousTab")
    static let nextTab = Notification.Name("nextTab")
    static let reopenClosedTab = Notification.Name("reopenClosedTab")

    // Zoom controls
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")

    // Picture in Picture
    static let togglePictureInPicture = Notification.Name("togglePictureInPicture")

    // Downloads
    static let toggleDownloads = Notification.Name("toggleDownloads")

    // Reading list
    static let closeAllOverlays = Notification.Name("closeAllOverlays")

    // Tab wheel
    static let showTabWheel = Notification.Name("showTabWheel")

    // Open URL in active tab (for agent/MCP)
    static let openURL = Notification.Name("openURL")

    // Open link in new tab (from context menu)
    static let openLinkInNewTab = Notification.Name("openLinkInNewTab")

}
