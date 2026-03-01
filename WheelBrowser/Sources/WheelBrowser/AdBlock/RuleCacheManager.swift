import Foundation
import WebKit

/// Manages cache validation and storage for compiled content blocking rules.
/// Supports per-source hashes so that built-in category rules are effectively permanent
/// until the app updates, and external lists are independently invalidated.
@MainActor
final class RuleCacheManager {

    /// Key for storing per-source configuration hashes in UserDefaults
    private let sourceHashesKey = "ContentBlockerSourceHashes"

    /// Legacy key (kept for migration)
    private let legacyVersionKey = "ContentBlockerRuleVersion"

    // MARK: - Per-Source Cache

    /// Load all stored source hashes
    private func loadSourceHashes() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: sourceHashesKey) as? [String: String] ?? [:]
    }

    /// Save a source hash after successful compilation
    func saveSourceHash(_ identifier: String, hash: String) {
        var hashes = loadSourceHashes()
        hashes[identifier] = hash
        UserDefaults.standard.set(hashes, forKey: sourceHashesKey)
    }

    /// Check whether a specific source's cached rules are still valid
    func isSourceCacheValid(_ identifier: String, hash: String) -> Bool {
        let hashes = loadSourceHashes()
        return hashes[identifier] == hash
    }

    /// Clear hash for a specific source
    func clearSourceHash(_ identifier: String) {
        var hashes = loadSourceHashes()
        hashes.removeValue(forKey: identifier)
        UserDefaults.standard.set(hashes, forKey: sourceHashesKey)
    }

    /// Clear all source hashes
    func clearAllSourceHashes() {
        UserDefaults.standard.removeObject(forKey: sourceHashesKey)
        // Also clear legacy key
        UserDefaults.standard.removeObject(forKey: legacyVersionKey)
    }

    // MARK: - Legacy Migration

    /// Remove old monolithic cache entry on first run after per-category migration.
    func clearLegacyCacheIfNeeded() async {
        let migrated = UserDefaults.standard.bool(forKey: "ContentBlockerMigratedToPerCategory")
        guard !migrated else { return }
        await removeCachedRules(forIdentifier: BlockingRules.ruleSetIdentifier)
        clearConfigurationHash()
        UserDefaults.standard.set(true, forKey: "ContentBlockerMigratedToPerCategory")
    }

    // MARK: - Cache Loading

    /// Attempts to load cached rules for a specific identifier from WKContentRuleListStore.
    /// Returns `nil` if no cached rules exist for this identifier.
    func loadCachedRules(forIdentifier identifier: String) async throws -> WKContentRuleList? {
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(
                forIdentifier: identifier
            ) { ruleList, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ruleList)
                }
            }
        }
    }

    // MARK: - Cache Removal

    /// Removes cached rules for a specific identifier from the WKContentRuleListStore.
    func removeCachedRules(forIdentifier identifier: String) async {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().removeContentRuleList(
                forIdentifier: identifier
            ) { error in
                if let error = error {
                    Log.AdBlock.error("Failed to remove cached rules for \(identifier): \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Legacy Compatibility

    /// Legacy: save a single configuration hash (used by old monolithic approach)
    func saveConfigurationHash(_ configurationHash: String) {
        UserDefaults.standard.set(configurationHash, forKey: legacyVersionKey)
    }

    /// Legacy: clear the single configuration hash
    func clearConfigurationHash() {
        UserDefaults.standard.removeObject(forKey: legacyVersionKey)
    }

    /// Legacy: check if single-hash cache is valid
    func isCacheValid(for configurationHash: String) -> Bool {
        let cachedHash = UserDefaults.standard.string(forKey: legacyVersionKey)
        return cachedHash == configurationHash
    }

    /// Legacy: load cached rules using the old single identifier
    func loadCachedRules(for configurationHash: String) async throws -> WKContentRuleList? {
        guard isCacheValid(for: configurationHash) else {
            return nil
        }
        return try await loadCachedRules(forIdentifier: BlockingRules.ruleSetIdentifier)
    }

    /// Legacy: remove cached rules using the old single identifier
    func removeCachedRules() async {
        await removeCachedRules(forIdentifier: BlockingRules.ruleSetIdentifier)
    }
}
