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

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("llmEndpoint") var llmEndpoint: String = "http://localhost:11434/v1"
    @AppStorage("lettaServerURL") var lettaServerURL: String = "http://localhost:8283"
    @AppStorage("selectedModel") var selectedModel: String = "llama3.2:latest"

    // MARK: - System Prompt Customization

    /// Custom system prompt for chat assistant. Empty string uses the default.
    @AppStorage("chatSystemPrompt") var chatSystemPrompt: String = ""

    // MARK: - Summarization (uses main LLM endpoint with dedicated model)
    @AppStorage("summarizationModel") var summarizationModel: String = "qwen-summarizer"

    // Summarization uses the main LLM endpoint
    var summarizationBaseURL: URL? {
        llmBaseURL
    }
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false
    @AppStorage("agentId") var agentId: String = ""

    // MARK: - Semantic Search (DIndex) Configuration

    /// Whether to use remote DIndex server for embedding storage/search
    @AppStorage("dindexEnabled") var dindexEnabled: Bool = false {
        didSet { notifyEmbeddingSettingsChanged() }
    }

    /// DIndex server endpoint URL
    @AppStorage("dindexEndpoint") var dindexEndpoint: String = "http://localhost:8080"

    /// DIndex API key (stored in UserDefaults for simplicity; move to Keychain for production)
    @AppStorage("dindexAPIKey") var dindexAPIKey: String = ""

    private func notifyEmbeddingSettingsChanged() {
        NotificationCenter.default.post(name: .embeddingSettingsChanged, object: nil)
    }

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

    /// Whether to use API key authentication for remote LLM endpoints
    @AppStorage("useAPIKey") var useAPIKey: Bool = false

    // MARK: - Dark Mode Settings (Web Content)

    /// Dark mode for web content - mode setting (auto, on, off)
    @AppStorage("darkModeMode") var darkModeModeRaw: String = DarkModeMode.off.rawValue {
        didSet {
            NotificationCenter.default.post(name: .darkModeChanged, object: nil)
        }
    }

    var darkModeMode: DarkModeMode {
        get { DarkModeMode(rawValue: darkModeModeRaw) ?? .off }
        set { darkModeModeRaw = newValue.rawValue }
    }

    /// Dark mode brightness adjustment (0-200, 100 is default)
    @AppStorage("darkModeBrightness") var darkModeBrightness: Double = 100 {
        didSet {
            NotificationCenter.default.post(name: .darkModeBrightnessChanged, object: nil)
        }
    }

    /// Dark mode contrast adjustment (0-200, 100 is default)
    @AppStorage("darkModeContrast") var darkModeContrast: Double = 100 {
        didSet {
            NotificationCenter.default.post(name: .darkModeBrightnessChanged, object: nil)
        }
    }

    // MARK: - Content Blocking Settings

    /// Master toggle for content blocking
    @AppStorage("adBlockingEnabled") var adBlockingEnabled: Bool = true {
        didSet {
            // Sync with ContentBlockerManager
            if adBlockingEnabled {
                // Re-enable with previously saved categories (or all if none)
                Task { @MainActor in
                    let manager = ContentBlockerManager.shared
                    if manager.enabledCategories.isEmpty {
                        manager.enableAll()
                    }
                    await manager.compileRules()
                }
            } else {
                // Disable all categories
                Task { @MainActor in
                    ContentBlockerManager.shared.disableAll()
                }
            }
        }
    }

    private init() {}
}
