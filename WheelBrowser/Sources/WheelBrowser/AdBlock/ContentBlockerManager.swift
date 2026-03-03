import Foundation
import WebKit

/// Manages content blocking rules for WKWebView using WKContentRuleListStore.
/// Compiles separate WKContentRuleList per source (built-in category or external filter list)
/// so that toggling categories is an instant add/remove operation without recompilation.
@MainActor
class ContentBlockerManager: ObservableObject {

    /// Shared singleton instance
    static let shared = ContentBlockerManager()

    /// Compiled content rule lists keyed by source identifier
    @Published private(set) var compiledRuleLists: [String: WKContentRuleList] = [:]

    /// Whether rules are currently being compiled
    @Published private(set) var isCompiling: Bool = false

    /// Last error encountered during compilation
    @Published private(set) var lastError: Error?

    /// Currently enabled blocking categories
    @Published var enabledCategories: Set<BlockingCategory> {
        didSet {
            saveEnabledCategories()
            if enabledCategories != oldValue {
                let added = enabledCategories.subtracting(oldValue)
                let removed = oldValue.subtracting(enabledCategories)
                Task {
                    // Remove disabled categories
                    for category in removed {
                        let id = Self.identifier(for: category)
                        compiledRuleLists.removeValue(forKey: id)
                    }
                    // Compile newly enabled categories
                    for category in added {
                        await compileCategoryRules(category)
                    }
                }
            }
        }
    }

    private let categoriesKey = "ContentBlockerEnabledCategories"

    /// Reference to blocking stats for tracking
    private let stats: BlockingStatsRecording

    /// Merger for combining built-in and external filter list rules
    private let rulesMerger: ExternalRulesMerger

    /// Cache manager for rule persistence and validation
    private let cacheManager = RuleCacheManager()

    /// Compilation pipeline for building WKContentRuleList from rule dictionaries
    private let compilationPipeline = RuleCompilationPipeline()

    /// Observer for filter list changes
    private var filterListObserver: NSObjectProtocol?

    private init() {
        self.stats = BlockingStats.shared
        self.rulesMerger = ExternalRulesMerger(externalRulesProvider: FilterListManager.shared)

        // Load saved categories or default to all enabled
        self.enabledCategories = Self.loadEnabledCategories()

        // Observe filter list changes
        setupFilterListObserver()
    }

    deinit {
        if let observer = filterListObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Set up observer for filter list changes
    private func setupFilterListObserver() {
        filterListObserver = NotificationCenter.default.addObserver(
            forName: .filterListsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshExternalRules()
            }
        }
    }

    // MARK: - Source Identifiers

    /// Identifier for a built-in category rule list
    static func identifier(for category: BlockingCategory) -> String {
        "WheelBrowser-\(category.rawValue)"
    }

    /// Identifier for an external filter list
    static func identifier(forExternal uuid: UUID) -> String {
        "WheelBrowser-ext-\(uuid.uuidString)"
    }

    // MARK: - Category Management

    /// Load enabled categories from UserDefaults
    private static func loadEnabledCategories() -> Set<BlockingCategory> {
        guard let savedCategories = UserDefaults.standard.array(forKey: "ContentBlockerEnabledCategories") as? [String] else {
            // Default: all categories enabled
            return Set(BlockingCategory.allCases)
        }

        let categories = savedCategories.compactMap { BlockingCategory(rawValue: $0) }
        return categories.isEmpty ? Set(BlockingCategory.allCases) : Set(categories)
    }

    /// Save enabled categories to UserDefaults
    private func saveEnabledCategories() {
        let categoryStrings = enabledCategories.map { $0.rawValue }
        UserDefaults.standard.set(categoryStrings, forKey: categoriesKey)
    }

    /// Check if a specific category is enabled
    func isEnabled(_ category: BlockingCategory) -> Bool {
        enabledCategories.contains(category)
    }

    /// Check whether a category is enabled from any context (reads UserDefaults directly).
    /// Use this from non-MainActor contexts like Tab.init().
    nonisolated static func isCategoryEnabled(_ category: BlockingCategory) -> Bool {
        guard let saved = UserDefaults.standard.array(forKey: "ContentBlockerEnabledCategories") as? [String] else {
            return true // default: all categories enabled
        }
        return saved.contains(category.rawValue)
    }

    /// Toggle a specific category
    func toggle(_ category: BlockingCategory) {
        if enabledCategories.contains(category) {
            enabledCategories.remove(category)
        } else {
            enabledCategories.insert(category)
        }
    }

    /// Enable a specific category
    func enable(_ category: BlockingCategory) {
        enabledCategories.insert(category)
    }

    /// Disable a specific category
    func disable(_ category: BlockingCategory) {
        enabledCategories.remove(category)
    }

    /// Enable all categories
    func enableAll() {
        enabledCategories = Set(BlockingCategory.allCases)
    }

    /// Disable all categories
    func disableAll() {
        enabledCategories = []
    }

    // MARK: - Rule Compilation

    /// Compiles and caches content blocking rules for all enabled sources
    func compileRules() async {
        guard !isCompiling else { return }
        guard !enabledCategories.isEmpty else {
            compiledRuleLists = [:]
            return
        }

        isCompiling = true
        lastError = nil

        // Clean up legacy monolithic cache on first run after migration
        await cacheManager.clearLegacyCacheIfNeeded()

        // Compile each enabled built-in category independently
        for category in enabledCategories {
            let identifier = Self.identifier(for: category)
            guard compiledRuleLists[identifier] == nil else { continue }

            let rules = BlockingRules.rules(for: category)
            guard !rules.isEmpty else { continue }

            // 1. Try loading from cache (with version validation)
            if cacheManager.isSourceCacheValid(identifier, hash: BlockingRules.ruleSetVersion) {
                do {
                    if let cached = try await cacheManager.loadCachedRules(forIdentifier: identifier) {
                        compiledRuleLists[identifier] = cached
                        continue
                    }
                } catch {
                    // Stale/corrupt cache entry — remove it and compile fresh
                    Log.AdBlock.warning("Cache lookup failed for \(category.rawValue), clearing: \(error.localizedDescription)")
                    await cacheManager.removeCachedRules(forIdentifier: identifier)
                    cacheManager.clearSourceHash(identifier)
                }
            } else {
                // Hash mismatch — remove stale cached rules
                await cacheManager.removeCachedRules(forIdentifier: identifier)
                cacheManager.clearSourceHash(identifier)
            }

            // 2. Compile fresh
            do {
                let compiled = try await compilationPipeline.compile(rules, identifier: identifier)
                compiledRuleLists[identifier] = compiled
                cacheManager.saveSourceHash(identifier, hash: BlockingRules.ruleSetVersion)
            } catch {
                Log.AdBlock.error("Failed to compile \(category.rawValue) (\(rules.count) rules): \(error.localizedDescription)")
                // Continue to next category — don't abort everything
            }
        }

        // Compile external filter list rules (splitting large lists into chunks)
        let externalRules = rulesMerger.gatherExternalRulesGrouped()
        for (listID, rules) in externalRules {
            let identifier = Self.identifier(forExternal: listID)
            if compiledRuleLists[identifier] == nil && !rules.isEmpty {
                do {
                    let compiledLists = try await compilationPipeline.compileLargeList(rules, identifier: identifier)
                    for (index, compiled) in compiledLists.enumerated() {
                        let key = compiledLists.count == 1 ? identifier : "\(identifier)-\(index)"
                        compiledRuleLists[key] = compiled
                    }
                } catch {
                    Log.AdBlock.warning("External list \(listID) failed to compile, skipping: \(error.localizedDescription)")
                }
            }
        }

        isCompiling = false
    }

    /// Compile rules for a single category
    private func compileCategoryRules(_ category: BlockingCategory) async {
        let identifier = Self.identifier(for: category)
        let rules = BlockingRules.rules(for: category)
        guard !rules.isEmpty else { return }

        do {
            if let cached = try await cacheManager.loadCachedRules(forIdentifier: identifier) {
                compiledRuleLists[identifier] = cached
            } else {
                let compiled = try await compilationPipeline.compile(rules, identifier: identifier)
                compiledRuleLists[identifier] = compiled
                cacheManager.saveSourceHash(identifier, hash: BlockingRules.ruleSetVersion)
            }
        } catch {
            Log.AdBlock.error("Failed to compile \(category.rawValue): \(error.localizedDescription)")
        }
    }

    /// Applies content blocking rules to a WKWebView configuration
    func applyRules(to configuration: WKWebViewConfiguration) async {
        // Ensure rules are compiled
        if compiledRuleLists.isEmpty && !isCompiling && !enabledCategories.isEmpty {
            await compileRules()
        }

        // Wait for compilation if in progress
        if isCompiling {
            for await compiling in $isCompiling.values where !compiling {
                break
            }
        }

        // Apply all compiled rule lists
        for ruleList in compiledRuleLists.values {
            configuration.userContentController.add(ruleList)
        }

        // Apply site allowlist LAST so ignore-previous-rules overrides blocking rules
        SiteAllowlistManager.shared.applyAllowlist(to: configuration)
    }

    /// Applies content blocking rules to an existing WKWebView
    func applyRules(to webView: WKWebView) async {
        // Ensure rules are compiled
        if compiledRuleLists.isEmpty && !isCompiling && !enabledCategories.isEmpty {
            await compileRules()
        }

        // Wait for compilation if in progress
        if isCompiling {
            for await compiling in $isCompiling.values where !compiling {
                break
            }
        }

        // Apply all compiled rule lists
        for ruleList in compiledRuleLists.values {
            webView.configuration.userContentController.add(ruleList)
        }

        // Apply site allowlist LAST so ignore-previous-rules overrides blocking rules
        SiteAllowlistManager.shared.applyAllowlist(to: webView)
    }

    /// Removes content blocking rules from a WKWebView
    func removeRules(from webView: WKWebView) {
        for ruleList in compiledRuleLists.values {
            webView.configuration.userContentController.remove(ruleList)
        }
        SiteAllowlistManager.shared.removeAllowlist(from: webView)
    }

    /// Refresh only external filter list rules (called when filter lists change)
    func refreshExternalRules() async {
        // Remove existing external rule lists
        let externalKeys = compiledRuleLists.keys.filter { $0.hasPrefix("WheelBrowser-ext-") }
        for key in externalKeys {
            compiledRuleLists.removeValue(forKey: key)
            await cacheManager.removeCachedRules(forIdentifier: key)
        }

        // Recompile external rules
        let externalRules = rulesMerger.gatherExternalRulesGrouped()
        for (listID, rules) in externalRules {
            let identifier = Self.identifier(forExternal: listID)
            guard !rules.isEmpty else { continue }
            let truncated = rules.count > RuleCompilationPipeline.maxRuleCount
                ? Array(rules.prefix(RuleCompilationPipeline.maxRuleCount))
                : rules
            if let compiled = try? await compilationPipeline.compile(truncated, identifier: identifier) {
                compiledRuleLists[identifier] = compiled
            }
        }

        // Invalidate cosmetic filter and scriptlet caches
        invalidateCosmeticCache()
        ScriptletInjector.shared.invalidateCache()
    }

    /// Removes all cached rules and recompiles everything
    func refreshRules() async {
        // Remove all from store
        for identifier in compiledRuleLists.keys {
            await cacheManager.removeCachedRules(forIdentifier: identifier)
        }
        cacheManager.clearAllSourceHashes()

        // Clear local cache
        compiledRuleLists = [:]

        // Recompile with current categories
        await compileRules()
    }

    // MARK: - Stats Tracking

    /// Record a page load for stats tracking
    func recordPageLoad() {
        guard !enabledCategories.isEmpty else { return }
        stats.recordPageLoad(enabledCategories: enabledCategories)
    }

    // MARK: - Cosmetic Filtering

    /// Cached cosmetic filter script
    private var cachedCosmeticScript: WKUserScript?

    /// Get a WKUserScript for cosmetic (element hiding) filters from all enabled filter lists
    func getCosmeticFilterScript() async -> WKUserScript? {
        if let cached = cachedCosmeticScript { return cached }
        let merged = await FilterListManager.shared.getMergedCosmeticFilters()
        let script = CosmeticFilterEngine.createUserScript(from: merged)
        cachedCosmeticScript = script
        return script
    }

    /// Invalidate cached cosmetic filter script (called when filter lists change)
    func invalidateCosmeticCache() {
        cachedCosmeticScript = nil
    }
}

// MARK: - Rule Count Information

extension ContentBlockerManager {

    /// Approximate rule counts by category (for display purposes)
    static let approximateRuleCounts: [BlockingCategory: Int] = [
        .ads: 85,
        .trackers: 65,
        .socialWidgets: 25,
        .annoyances: 45
    ]

    /// Total approximate rules for enabled categories
    var approximateTotalRules: Int {
        enabledCategories.reduce(0) { sum, category in
            sum + (Self.approximateRuleCounts[category] ?? 0)
        }
    }

    /// Description of blocking status
    var statusDescription: String {
        if enabledCategories.isEmpty {
            return "Content blocking disabled"
        } else if enabledCategories.count == BlockingCategory.allCases.count {
            return "Full protection enabled (~\(approximateTotalRules) rules)"
        } else {
            let names = enabledCategories.map { $0.displayName }.sorted().joined(separator: ", ")
            return "Blocking: \(names)"
        }
    }
}

// MARK: - Backward Compatibility

extension ContentBlockerManager {
    /// Legacy accessor — returns the first compiled rule list (for code that expects a single list)
    var contentRuleList: WKContentRuleList? {
        compiledRuleLists.values.first
    }
}

// MARK: - Errors

enum ContentBlockerError: LocalizedError {
    case compilationFailed
    case ruleListNotFound
    case noRulesEnabled

    var errorDescription: String? {
        switch self {
        case .compilationFailed:
            return "Failed to compile content blocking rules"
        case .ruleListNotFound:
            return "Content rule list not found in cache"
        case .noRulesEnabled:
            return "No blocking categories are enabled"
        }
    }
}
