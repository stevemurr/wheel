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
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false
    @AppStorage("agentId") var agentId: String = ""

    // MARK: - Embedding Configuration

    /// Embedding provider: "openai", "voyage", "local", or "custom"
    @AppStorage("embeddingProvider") var embeddingProvider: String = "openai" {
        didSet { notifyEmbeddingSettingsChanged() }
    }

    /// Custom embedding endpoint URL (used when provider is "custom")
    @AppStorage("embeddingEndpoint") var embeddingEndpoint: String = "https://api.openai.com/v1/embeddings"

    /// Embedding model name
    @AppStorage("embeddingModel") var embeddingModel: String = "text-embedding-3-small"

    /// Embedding dimensions
    @AppStorage("embeddingDimensions") var embeddingDimensions: Int = 1536 {
        didSet {
            if oldValue != embeddingDimensions {
                // Dimensions changed - must clear index
                NotificationCenter.default.post(name: .embeddingDimensionsChanged, object: nil)
            }
            notifyEmbeddingSettingsChanged()
        }
    }

    /// Whether semantic search indexing is enabled
    @AppStorage("semanticSearchEnabled") var semanticSearchEnabled: Bool = true {
        didSet { notifyEmbeddingSettingsChanged() }
    }

    private func notifyEmbeddingSettingsChanged() {
        NotificationCenter.default.post(name: .embeddingSettingsChanged, object: nil)
    }

    /// Whether the left tab sidebar is expanded (showing full tab names) or collapsed (icons only)
    @AppStorage("tabSidebarExpanded") var tabSidebarExpanded: Bool = true

    /// Whether the tab dock auto-hides (like macOS Dock)
    @AppStorage("tabDockAutoHide") var tabDockAutoHide: Bool = false

    /// App appearance mode (system, light, or dark)
    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue {
        didSet {
            applyAppearance()
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    /// Apply the current appearance mode to the app
    func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearance
    }

    /// Whether to use API key authentication for remote LLM endpoints
    @AppStorage("useAPIKey") var useAPIKey: Bool = false

    // MARK: - API Key (stored securely in Keychain)

    /// The LLM API key stored securely in the Keychain
    /// Setting this property will trigger objectWillChange to update any observing views
    var llmAPIKey: String {
        get {
            KeychainHelper.shared.retrieve(forKey: KeychainHelper.Keys.llmAPIKey) ?? ""
        }
        set {
            objectWillChange.send()
            if newValue.isEmpty {
                KeychainHelper.shared.delete(forKey: KeychainHelper.Keys.llmAPIKey)
            } else {
                KeychainHelper.shared.save(newValue, forKey: KeychainHelper.Keys.llmAPIKey)
            }
        }
    }

    /// Whether an API key is currently configured
    var hasAPIKey: Bool {
        !llmAPIKey.isEmpty
    }

    // MARK: - Embedding API Key (stored securely in Keychain)

    /// The Embedding API key stored securely in the Keychain
    var embeddingAPIKey: String {
        get {
            KeychainHelper.shared.retrieve(forKey: KeychainHelper.Keys.embeddingAPIKey) ?? ""
        }
        set {
            objectWillChange.send()
            if newValue.isEmpty {
                KeychainHelper.shared.delete(forKey: KeychainHelper.Keys.embeddingAPIKey)
            } else {
                KeychainHelper.shared.save(newValue, forKey: KeychainHelper.Keys.embeddingAPIKey)
            }
        }
    }

    /// Whether an embedding API key is configured
    var hasEmbeddingAPIKey: Bool {
        !embeddingAPIKey.isEmpty
    }

    /// Create an embedding service based on current settings
    func makeEmbeddingService() -> any EmbeddingService {
        switch embeddingProvider {
        case "openai":
            return APIEmbeddingService(
                endpoint: URL(string: "https://api.openai.com/v1/embeddings")!,
                apiKey: embeddingAPIKey,
                modelName: embeddingModel,
                dimensions: embeddingDimensions
            )
        case "voyage":
            return APIEmbeddingService(
                endpoint: URL(string: "https://api.voyageai.com/v1/embeddings")!,
                apiKey: embeddingAPIKey,
                modelName: embeddingModel,
                dimensions: embeddingDimensions
            )
        case "local":
            return LocalEmbeddingService()
        case "custom":
            // Auto-append /embeddings if the endpoint doesn't already have it
            let endpoint = normalizeEmbeddingEndpoint(embeddingEndpoint)
            return APIEmbeddingService(
                endpoint: URL(string: endpoint) ?? URL(string: "http://localhost:8080/embeddings")!,
                apiKey: embeddingAPIKey.isEmpty ? nil : embeddingAPIKey,
                modelName: embeddingModel,
                dimensions: embeddingDimensions
            )
        default:
            return LocalEmbeddingService()
        }
    }

    /// Normalize embedding endpoint to ensure it ends with /embeddings
    private func normalizeEmbeddingEndpoint(_ endpoint: String) -> String {
        var url = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing slash if present
        while url.hasSuffix("/") {
            url.removeLast()
        }
        // Append /embeddings if not already present
        if !url.hasSuffix("/embeddings") {
            url += "/embeddings"
        }
        return url
    }

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

    // Individual category toggles (stored via ContentBlockerManager)
    // These are computed properties that delegate to ContentBlockerManager

    private init() {}

    var lettaBaseURL: URL? {
        URL(string: lettaServerURL)
    }

    var llmBaseURL: URL? {
        URL(string: llmEndpoint)
    }

    // MARK: - Category Convenience Methods

    /// Check if a blocking category is enabled
    @MainActor
    func isBlockingCategoryEnabled(_ category: BlockingCategory) -> Bool {
        guard adBlockingEnabled else { return false }
        return ContentBlockerManager.shared.isEnabled(category)
    }

    /// Toggle a blocking category
    @MainActor
    func toggleBlockingCategory(_ category: BlockingCategory) {
        ContentBlockerManager.shared.toggle(category)
        // If any category is now enabled, ensure master toggle is on
        if !ContentBlockerManager.shared.enabledCategories.isEmpty {
            adBlockingEnabled = true
        }
    }

    /// Set all blocking categories at once
    @MainActor
    func setBlockingCategories(_ categories: Set<BlockingCategory>) {
        if categories.isEmpty {
            adBlockingEnabled = false
        } else {
            adBlockingEnabled = true
            ContentBlockerManager.shared.enabledCategories = categories
        }
    }
}
