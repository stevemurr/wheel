import Foundation

extension AppSettings {

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

    var lettaBaseURL: URL? {
        URL(string: lettaServerURL)
    }

    var llmBaseURL: URL? {
        URL(string: llmEndpoint)
    }
}
