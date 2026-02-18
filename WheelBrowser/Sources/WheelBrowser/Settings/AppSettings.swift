import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("llmEndpoint") var llmEndpoint: String = "http://localhost:11434/v1"
    @AppStorage("lettaServerURL") var lettaServerURL: String = "http://localhost:8283"
    @AppStorage("selectedModel") var selectedModel: String = "llama3.2:latest"
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false
    @AppStorage("agentId") var agentId: String = ""

    /// Whether the left tab sidebar is expanded (showing full tab names) or collapsed (icons only)
    @AppStorage("tabSidebarExpanded") var tabSidebarExpanded: Bool = true

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
