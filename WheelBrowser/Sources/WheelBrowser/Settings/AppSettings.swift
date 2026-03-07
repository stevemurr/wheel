import Foundation
import SwiftUI
import AppKit

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

class AppSettings: ObservableObject, @unchecked Sendable {
    static let shared = AppSettings()
    static let hiddenTabScaleKey = "hiddenTabScale"
    static let shownTabScaleKey = "shownTabScale"
    static let defaultHiddenTabScale = 1.0
    static let defaultShownTabScale = 1.0
    static let hiddenTabScaleRange: ClosedRange<Double> = 0.7...1.7
    static let shownTabScaleRange: ClosedRange<Double> = 0.75...1.6
    static let tabScaleStep = 0.05

    // MARK: - System Prompt Customization

    /// Custom system prompt for chat assistant. Empty string uses the default.
    @AppStorage("chatSystemPrompt") var chatSystemPrompt: String = ""
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false

    // MARK: - Semantic Search Configuration

    /// Whether on-device semantic search is enabled (indexes pages locally via CoreML embeddings)
    @AppStorage("semanticSearchEnabled") var semanticSearchEnabled: Bool = true

    /// Whether the left tab sidebar is expanded (showing full tab names) or collapsed (icons only)
    @AppStorage("tabSidebarExpanded") var tabSidebarExpanded: Bool = true

    /// Whether the tab dock auto-hides (like macOS Dock)
    @AppStorage("tabDockAutoHide") var tabDockAutoHide: Bool = false

    /// Scale factor for collapsed binder-tab peeks in the left tab dock
    @AppStorage(hiddenTabScaleKey) var hiddenTabScale: Double = defaultHiddenTabScale

    /// Scale factor for expanded thumbnail tabs in the left tab dock
    @AppStorage(shownTabScaleKey) var shownTabScale: Double = defaultShownTabScale

    /// Whether the MCP server should start automatically on app launch
    @AppStorage("mcpServerEnabled") var mcpServerEnabled: Bool = true

    /// Whether link previews are enabled (Wikipedia-style hover previews)
    @AppStorage("linkPreviewEnabled") var linkPreviewEnabled: Bool = true

    /// App appearance mode (system, light, or dark)
    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue {
        didSet {
            applyAppearance()
        }
    }

    private init() {}
}
