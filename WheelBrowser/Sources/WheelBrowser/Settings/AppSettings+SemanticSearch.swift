import Foundation
import DIndexClient

extension AppSettings {

    /// Create a DIndexClient based on current settings
    /// Returns nil if DIndex is disabled or the endpoint is invalid
    func makeDIndexClient() -> DIndexClient? {
        guard dindexEnabled else { return nil }
        guard let url = URL(string: dindexEndpoint) else { return nil }
        return DIndexClient(
            baseURL: url,
            apiKey: dindexAPIKey.isEmpty ? nil : dindexAPIKey
        )
    }
}
