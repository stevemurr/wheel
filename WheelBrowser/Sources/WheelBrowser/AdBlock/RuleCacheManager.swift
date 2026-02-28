import Foundation
import WebKit

/// Manages cache validation and storage for compiled content blocking rules.
/// Handles checking if cached rules are still valid, loading from cache, and saving configuration hashes.
@MainActor
final class RuleCacheManager {

    /// Key for storing rule version/configuration hash in UserDefaults
    private let versionKey = "ContentBlockerRuleVersion"

    // MARK: - Cache Validation

    /// Checks whether the cached rules match the current configuration hash.
    /// - Parameter configurationHash: The hash representing the current rule configuration.
    /// - Returns: `true` if the cached hash matches the provided hash.
    func isCacheValid(for configurationHash: String) -> Bool {
        let cachedHash = UserDefaults.standard.string(forKey: versionKey)
        return cachedHash == configurationHash
    }

    /// Attempts to load cached rules from WKContentRuleListStore.
    /// Returns `nil` if the cache is invalid or no cached rules exist.
    /// - Parameter configurationHash: The hash representing the current rule configuration.
    /// - Returns: The cached `WKContentRuleList`, or `nil` if unavailable or stale.
    func loadCachedRules(for configurationHash: String) async throws -> WKContentRuleList? {
        guard isCacheValid(for: configurationHash) else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(
                forIdentifier: BlockingRules.ruleSetIdentifier
            ) { ruleList, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ruleList)
                }
            }
        }
    }

    // MARK: - Cache Updates

    /// Saves the configuration hash after successful compilation.
    /// - Parameter configurationHash: The hash to persist.
    func saveConfigurationHash(_ configurationHash: String) {
        UserDefaults.standard.set(configurationHash, forKey: versionKey)
    }

    /// Clears the cached configuration hash, forcing recompilation on next access.
    func clearConfigurationHash() {
        UserDefaults.standard.removeObject(forKey: versionKey)
    }

    /// Removes cached rules from the WKContentRuleListStore.
    func removeCachedRules() async {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().removeContentRuleList(
                forIdentifier: BlockingRules.ruleSetIdentifier
            ) { error in
                if let error = error {
                    Log.AdBlock.error("Failed to remove cached rules: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
}
