import Foundation
import WebKit

/// Manages content blocking rules for WKWebView using WKContentRuleListStore
/// Handles compilation, caching, and application of blocking rules with category support
@MainActor
class ContentBlockerManager: ObservableObject {

    /// Shared singleton instance
    static let shared = ContentBlockerManager()

    /// The compiled content rule list, cached after first compilation
    @Published private(set) var contentRuleList: WKContentRuleList?

    /// Whether rules are currently being compiled
    @Published private(set) var isCompiling: Bool = false

    /// Last error encountered during compilation
    @Published private(set) var lastError: Error?

    /// Currently enabled blocking categories
    @Published var enabledCategories: Set<BlockingCategory> {
        didSet {
            saveEnabledCategories()
            // Recompile rules when categories change
            if enabledCategories != oldValue {
                Task {
                    await refreshRules()
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
                await self?.refreshRules()
            }
        }
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

    /// Unique identifier for current category configuration (includes filter lists)
    private var currentConfigurationHash: String {
        rulesMerger.configurationHash(for: enabledCategories)
    }

    /// Compiles and caches the content blocking rules for enabled categories
    func compileRules() async {
        guard !isCompiling else { return }
        guard !enabledCategories.isEmpty else {
            // No categories enabled, clear rules
            contentRuleList = nil
            return
        }

        isCompiling = true
        lastError = nil

        do {
            // Check if we have a cached version with the same configuration
            let configHash = currentConfigurationHash
            if let cachedRules = try await cacheManager.loadCachedRules(for: configHash) {
                self.contentRuleList = cachedRules
                isCompiling = false
                return
            }

            // Compile new rules
            let rules = try await compileNewRules()
            self.contentRuleList = rules

            // Save configuration hash for cache validation
            cacheManager.saveConfigurationHash(configHash)

        } catch {
            self.lastError = error
            Log.AdBlock.error("Failed to compile rules: \(error.localizedDescription)")
        }

        isCompiling = false
    }

    /// Applies content blocking rules to a WKWebView configuration
    /// Call this before creating the WKWebView or after rules are compiled
    func applyRules(to configuration: WKWebViewConfiguration) async {
        // Ensure rules are compiled
        if contentRuleList == nil && !isCompiling && !enabledCategories.isEmpty {
            await compileRules()
        }

        // Wait for compilation if in progress
        if isCompiling {
            for await compiling in $isCompiling.values where !compiling {
                break
            }
        }

        // Apply rules if available
        if let rules = contentRuleList {
            configuration.userContentController.add(rules)
        }
    }

    /// Applies content blocking rules to an existing WKWebView
    /// Use this to enable/disable blocking on an already-created web view
    func applyRules(to webView: WKWebView) async {
        // Ensure rules are compiled
        if contentRuleList == nil && !isCompiling && !enabledCategories.isEmpty {
            await compileRules()
        }

        // Wait for compilation if in progress
        if isCompiling {
            for await compiling in $isCompiling.values where !compiling {
                break
            }
        }

        // Apply rules if available
        if let rules = contentRuleList {
            webView.configuration.userContentController.add(rules)
        }
    }

    /// Removes content blocking rules from a WKWebView
    func removeRules(from webView: WKWebView) {
        if let rules = contentRuleList {
            webView.configuration.userContentController.remove(rules)
        }
    }

    /// Removes all cached rules and recompiles with current categories
    func refreshRules() async {
        // Remove from store and clear configuration hash
        await cacheManager.removeCachedRules()
        cacheManager.clearConfigurationHash()

        // Clear local cache
        contentRuleList = nil

        // Recompile with current categories
        await compileRules()
    }

    // MARK: - Stats Tracking

    /// Record a page load for stats tracking
    func recordPageLoad() {
        guard !enabledCategories.isEmpty else { return }
        stats.recordPageLoad(enabledCategories: enabledCategories)
    }

    // MARK: - Private Methods

    /// Compiles new rules by gathering built-in and external sources,
    /// then delegating to the compilation pipeline.
    private func compileNewRules() async throws -> WKContentRuleList {
        let (builtInRules, externalRules) = rulesMerger.gatherRules(for: enabledCategories)

        return try await compilationPipeline.compileWithFallback(
            builtInRules: builtInRules,
            externalRules: externalRules
        )
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
