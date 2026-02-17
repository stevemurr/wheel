import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
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

                Divider()

                Button("Focus AI Chat") {
                    NotificationCenter.default.post(name: .focusAISidebar, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
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
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

extension Notification.Name {
    static let newTab = Notification.Name("newTab")
    static let closeTab = Notification.Name("closeTab")
    static let toggleSidebar = Notification.Name("toggleSidebar")
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

    // Zoom controls
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
}
