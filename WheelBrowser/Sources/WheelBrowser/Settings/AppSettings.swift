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

    @AppStorage("lettaServerURL") var lettaServerURL: String = "http://localhost:8283"

    // MARK: - System Prompt Customization

    /// Custom system prompt for chat assistant. Empty string uses the default.
    @AppStorage("chatSystemPrompt") var chatSystemPrompt: String = ""
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false
    @AppStorage("agentId") var agentId: String = ""

    // MARK: - Semantic Search Configuration

    /// Whether on-device semantic search is enabled (indexes pages locally via CoreML embeddings)
    @AppStorage("semanticSearchEnabled") var semanticSearchEnabled: Bool = true

    /// Whether the left tab sidebar is expanded (showing full tab names) or collapsed (icons only)
    @AppStorage("tabSidebarExpanded") var tabSidebarExpanded: Bool = true

    /// Whether the tab dock auto-hides (like macOS Dock)
    @AppStorage("tabDockAutoHide") var tabDockAutoHide: Bool = false

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

    // MARK: - Widget System Settings

    /// BFF proxy endpoint for widget data fetching (empty = direct HTTP)
    @AppStorage("bffEndpoint") var bffEndpoint: String = ""

    private init() {}
}
