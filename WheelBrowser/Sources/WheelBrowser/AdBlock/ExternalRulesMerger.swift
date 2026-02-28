import Foundation

/// Protocol for providing external filter list rules.
/// Enables dependency injection for testability.
@MainActor
protocol ExternalRulesProvider {
    /// Returns all currently enabled external rules as WebKit content blocker JSON dictionaries.
    func getEnabledRules() -> [[String: Any]]

    /// Returns a stable identifier string for currently enabled filter lists, used for cache invalidation.
    var enabledFilterListIDs: String { get }
}

// MARK: - FilterListManager conformance

extension FilterListManager: ExternalRulesProvider {}

// MARK: - ExternalRulesMerger

/// Merges built-in blocking rules with external filter list rules into a unified rule set.
/// Responsible for gathering rules from enabled categories and external providers,
/// and computing configuration hashes for cache invalidation.
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

    /// Computes a configuration hash that uniquely identifies the current rule configuration.
    /// Used for cache invalidation -- if the hash changes, rules need to be recompiled.
    /// - Parameter enabledCategories: The set of currently enabled blocking categories.
    /// - Returns: A string hash representing the current configuration.
    func configurationHash(for enabledCategories: Set<BlockingCategory>) -> String {
        let sortedCategories = enabledCategories.map { $0.rawValue }.sorted().joined(separator: "-")
        let filterListIDs = externalRulesProvider.enabledFilterListIDs
        return "\(BlockingRules.ruleSetVersion)-\(sortedCategories)-\(filterListIDs)"
    }
}
