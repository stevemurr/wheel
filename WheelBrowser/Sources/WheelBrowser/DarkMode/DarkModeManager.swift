import Foundation
import WebKit

/// Dark mode setting modes
enum DarkModeMode: String, CaseIterable {
    case auto = "auto"
    case on = "on"
    case off = "off"

    var displayName: String {
        switch self {
        case .auto: return "Auto (System)"
        case .on: return "Always On"
        case .off: return "Always Off"
        }
    }
}

/// Manages dark mode for web content across all tabs
@MainActor
class DarkModeManager: ObservableObject {
    static let shared = DarkModeManager()

    @Published var isEnabled: Bool = false

    private init() {
        // Sync with AppSettings on init
        updateFromSettings()

        // Observe system appearance changes for auto mode
        setupSystemAppearanceObserver()
    }

    // MARK: - Public API

    /// Get a WKUserScript for injecting dark mode at document start
    func getUserScript() -> WKUserScript {
        let shouldEnable = shouldApplyDarkMode()
        let script = DarkModeScripts.generateBundle(
            enabled: shouldEnable,
            brightness: AppSettings.shared.darkModeBrightness,
            contrast: AppSettings.shared.darkModeContrast
        )

        return WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Determine if dark mode should be applied based on settings
    func shouldApplyDarkMode(for url: URL? = nil) -> Bool {
        let settings = AppSettings.shared

        // Check site exceptions (future feature)
        // if let url = url, isExcluded(url) { return false }

        switch settings.darkModeMode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            return isSystemInDarkMode()
        }
    }

    /// Toggle dark mode on a specific tab
    func toggle(on tab: Tab) {
        let settings = AppSettings.shared

        // Toggle the mode setting
        switch settings.darkModeMode {
        case .auto, .off:
            settings.darkModeMode = .on
        case .on:
            settings.darkModeMode = .off
        }

        // Apply to the tab
        applyToTab(tab)
    }

    /// Apply current dark mode state to a tab
    func applyToTab(_ tab: Tab) {
        let shouldEnable = shouldApplyDarkMode()
        let script = shouldEnable ? DarkModeScripts.enableScript() : DarkModeScripts.disableScript()

        tab.webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[DarkMode] Error applying to tab: \(error.localizedDescription)")
            }
        }

        isEnabled = shouldEnable
    }

    /// Apply dark mode to all existing tabs
    func applyToExistingTabs(_ tabs: [Tab]) {
        for tab in tabs {
            applyToTab(tab)
        }
    }

    /// Update brightness/contrast on all tabs
    func updateBrightnessContrast(on tabs: [Tab]) {
        let settings = AppSettings.shared
        let script = DarkModeScripts.updateCSSScript(
            brightness: settings.darkModeBrightness,
            contrast: settings.darkModeContrast
        )

        for tab in tabs {
            tab.webView.evaluateJavaScript(script) { _, _ in }
        }
    }

    // MARK: - Private

    /// Update manager state from AppSettings
    func updateFromSettings() {
        isEnabled = shouldApplyDarkMode()
    }

    /// Check if system is in dark mode
    private func isSystemInDarkMode() -> Bool {
        if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return appearance == .darkAqua
        }
        return false
    }

    /// Setup observer for system appearance changes
    private func setupSystemAppearanceObserver() {
        // Observe effective appearance changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if AppSettings.shared.darkModeMode == .auto {
                    self.updateFromSettings()
                    // Notify that dark mode state changed
                    NotificationCenter.default.post(name: .darkModeChanged, object: nil)
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let darkModeChanged = Notification.Name("darkModeChanged")
    static let darkModeBrightnessChanged = Notification.Name("darkModeBrightnessChanged")
    static let toggleDarkMode = Notification.Name("toggleDarkMode")
}
