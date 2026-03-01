import Foundation

/// Protocol for providing external filter list rules.
/// Enables dependency injection for testability.
@MainActor
protocol ExternalRulesProvider {
    /// Returns all currently enabled external rules as WebKit content blocker JSON dictionaries.
    func getEnabledRules() -> [[String: Any]]

    /// Returns a stable identifier string for currently enabled filter lists, used for cache invalidation.
    var enabledFilterListIDs: String { get }

    /// Returns enabled rules grouped by filter list ID
    func getEnabledRulesGrouped() -> [UUID: [[String: Any]]]
}

// MARK: - FilterListManager conformance

extension FilterListManager: ExternalRulesProvider {}

// MARK: - ExternalRulesMerger

/// Merges built-in blocking rules with external filter list rules into a unified rule set.
/// Responsible for gathering rules from enabled categories and external providers,
/// computing configuration hashes for cache invalidation, and deduplicating rules.
@MainActor
final class ExternalRulesMerger {

    private let externalRulesProvider: ExternalRulesProvider

    /// Creates a merger with the given external rules provider.
    /// - Parameter externalRulesProvider: The provider of external filter list rules.
    init(externalRulesProvider: ExternalRulesProvider) {
        self.externalRulesProvider = externalRulesProvider
    }

    /// Gathers built-in rules for the given categories and external rules from the provider.
    /// - Parameter enabledCategories: The set of currently enabled blocking categories.
    /// - Returns: A tuple of (builtInRules, externalRules).
    func gatherRules(
        for enabledCategories: Set<BlockingCategory>
    ) -> (builtIn: [[String: Any]], external: [[String: Any]]) {
        let builtInRules = BlockingRules.rules(for: enabledCategories)
        let externalRules = externalRulesProvider.getEnabledRules()
        return (builtInRules, externalRules)
    }

    /// Gathers external rules grouped by filter list ID for per-list compilation.
    func gatherExternalRulesGrouped() -> [UUID: [[String: Any]]] {
        externalRulesProvider.getEnabledRulesGrouped()
    }

    /// Gathers deduplicated external rules grouped by filter list ID.
    /// Removes rules whose url-filter + action type already exist in built-in rules.
    func gatherDeduplicatedExternalRules(
        for enabledCategories: Set<BlockingCategory>
    ) -> [UUID: [[String: Any]]] {
        let builtInRules = BlockingRules.rules(for: enabledCategories)
        let builtInSignatures = Set(builtInRules.compactMap { ruleSignature($0) })

        var grouped = externalRulesProvider.getEnabledRulesGrouped()
        for (listID, rules) in grouped {
            grouped[listID] = rules.filter { rule in
                guard let sig = ruleSignature(rule) else { return true }
                return !builtInSignatures.contains(sig)
            }
        }
        return grouped
    }

    /// Computes a configuration hash that uniquely identifies the current rule configuration.
    func configurationHash(for enabledCategories: Set<BlockingCategory>) -> String {
        let sortedCategories = enabledCategories.map { $0.rawValue }.sorted().joined(separator: "-")
        let filterListIDs = externalRulesProvider.enabledFilterListIDs
        return "\(BlockingRules.ruleSetVersion)-\(sortedCategories)-\(filterListIDs)"
    }

    // MARK: - Deduplication

    /// Creates a signature string for a rule based on url-filter and action type.
    private func ruleSignature(_ rule: [String: Any]) -> String? {
        guard let trigger = rule["trigger"] as? [String: Any],
              let urlFilter = trigger["url-filter"] as? String,
              let action = rule["action"] as? [String: Any],
              let actionType = action["type"] as? String else {
            return nil
        }
        return "\(urlFilter)|\(actionType)"
    }
}
