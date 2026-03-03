import Foundation

// MARK: - Filter List Manager

/// Singleton manager for filter list subscriptions
@MainActor
class FilterListManager: ObservableObject {

    /// Shared instance
    static let shared = FilterListManager()

    /// All subscribed filter lists
    @Published private(set) var filterLists: [FilterList] = []

    /// Whether an update is in progress
    @Published private(set) var isUpdating: Bool = false

    /// Last error encountered
    @Published private(set) var lastError: String?

    /// Progress of current update (0.0 - 1.0)
    @Published private(set) var updateProgress: Double = 0

    /// Cached cosmetic filters per filter list ID
    private(set) var cosmeticFilters: [UUID: ProcessedCosmeticFilters] = [:]

    /// Cached scriptlet rules per filter list ID
    private(set) var scriptletRules: [UUID: [ScriptletRule]] = [:]

    /// Storage keys
    private let filterListsKey = "FilterListSubscriptions"
    private let rulesDirectoryName = "FilterLists"
    private let converterVersionKey = "FilterListConverterVersion"

    /// Current converter version - increment when converter logic changes
    private let currentConverterVersion = 4

    /// Directory for storing converted rules
    private var rulesDirectory: URL {
        FileManager.appSupportDirectory.appendingPathComponent(rulesDirectoryName)
    }

    private init() {
        loadFilterLists()
        ensureDirectoryExists()
        checkConverterVersion()

        // Auto-download enabled filter lists that haven't been fetched yet
        if needsUpdate {
            Task { @MainActor in
                await updateAll()
            }
        }
    }

    /// Check if converter version changed and clear rules if needed
    private func checkConverterVersion() {
        let storedVersion = UserDefaults.standard.integer(forKey: converterVersionKey)
        if storedVersion != currentConverterVersion {
            Log.AdBlock.info("Converter version changed (\(storedVersion) -> \(currentConverterVersion)), clearing stored rules")
            clearStoredRules()
            UserDefaults.standard.set(currentConverterVersion, forKey: converterVersionKey)
        }
    }

    // MARK: - Filter List Management

    /// Add a new filter list
    func addFilterList(name: String, url: URL) {
        let filterList = FilterList(name: name, url: url, isEnabled: true)
        filterLists.append(filterList)
        saveFilterLists()
    }

    /// Remove a filter list
    func removeFilterList(_ filterList: FilterList) {
        filterLists.removeAll { $0.id == filterList.id }

        // Remove stored rules
        let rulesFile = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString).json")
        try? FileManager.default.removeItem(at: rulesFile)

        saveFilterLists()
        notifyRulesChanged()
    }

    /// Toggle a filter list enabled state
    func toggleFilterList(_ filterList: FilterList) {
        guard let index = filterLists.firstIndex(where: { $0.id == filterList.id }) else { return }
        filterLists[index].isEnabled.toggle()
        saveFilterLists()
        notifyRulesChanged()
    }

    /// Set enabled state for a filter list
    func setEnabled(_ enabled: Bool, for filterList: FilterList) {
        guard let index = filterLists.firstIndex(where: { $0.id == filterList.id }) else { return }
        filterLists[index].isEnabled = enabled
        saveFilterLists()
        notifyRulesChanged()
    }

    // MARK: - Update Methods

    /// Update all enabled filter lists concurrently
    func updateAll(forceUpdate: Bool = false) async {
        guard !isUpdating else { return }

        isUpdating = true
        updateProgress = 0
        lastError = nil

        let enabledLists = filterLists.filter { $0.isEnabled }
        let totalCount = enabledLists.count

        // Fetch all lists concurrently using a task group
        var results: [(FilterList, Result<Bool, Error>)] = []

        await withTaskGroup(of: (FilterList, Result<Bool, Error>).self) { group in
            for filterList in enabledLists {
                group.addTask {
                    do {
                        let fetcher = FilterListFetcher.shared
                        guard try await fetcher.fetchAndProcess(filterList, forceUpdate: forceUpdate) != nil else {
                            return (filterList, .success(false))
                        }
                        return (filterList, .success(true))
                    } catch {
                        return (filterList, .failure(error))
                    }
                }
            }

            var completed = 0
            for await result in group {
                results.append(result)
                completed += 1
                await MainActor.run {
                    self.updateProgress = Double(completed) / Double(totalCount)
                }
            }
        }

        // Process results back on main actor
        var hasChanges = false
        for (filterList, result) in results {
            switch result {
            case .success(let updated):
                if updated {
                    // Re-fetch and store since the task group couldn't mutate our state
                    do {
                        let changed = try await updateFilterList(filterList, forceUpdate: forceUpdate)
                        if changed { hasChanges = true }
                    } catch {
                        if let listIndex = filterLists.firstIndex(where: { $0.id == filterList.id }) {
                            filterLists[listIndex].lastError = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                if let listIndex = filterLists.firstIndex(where: { $0.id == filterList.id }) {
                    filterLists[listIndex].lastError = error.localizedDescription
                }
                Log.AdBlock.error("Failed to update \(filterList.name): \(error)")
            }
        }

        isUpdating = false

        if hasChanges {
            saveFilterLists()
            notifyRulesChanged()
        }
    }

    /// Update a single filter list
    @discardableResult
    func updateFilterList(_ filterList: FilterList, forceUpdate: Bool = false) async throws -> Bool {
        let fetcher = FilterListFetcher.shared

        guard let result = try await fetcher.fetchAndProcess(filterList, forceUpdate: forceUpdate) else {
            // No changes
            return false
        }

        // Update the filter list in our array
        if let index = filterLists.firstIndex(where: { $0.id == filterList.id }) {
            filterLists[index] = result.filterList
        }

        // Store the converted rules
        try storeRules(result.rules, for: result.filterList)

        // Cache cosmetic filters and scriptlet rules in memory
        cosmeticFilters[filterList.id] = result.cosmeticFilters
        scriptletRules[filterList.id] = result.scriptletRules

        // Store cosmetic filters to disk for persistence
        storeCosmeticFilters(result.cosmeticFilters, for: filterList)
        storeScriptletRules(result.scriptletRules, for: filterList)

        return true
    }

    // MARK: - Rule Access

    /// Get all enabled rules for ContentBlockerManager
    func getEnabledRules() -> [[String: Any]] {
        var allRules: [[String: Any]] = []

        for filterList in filterLists where filterList.isEnabled {
            if let rules = loadRules(for: filterList) {
                allRules.append(contentsOf: rules)
            }
        }

        return allRules
    }

    /// Get enabled rules grouped by filter list ID (for per-list compilation)
    func getEnabledRulesGrouped() -> [UUID: [[String: Any]]] {
        var grouped: [UUID: [[String: Any]]] = [:]
        for filterList in filterLists where filterList.isEnabled {
            if let rules = loadRules(for: filterList) {
                grouped[filterList.id] = rules
            }
        }
        return grouped
    }

    /// Get enabled filter list IDs (for cache invalidation)
    var enabledFilterListIDs: String {
        filterLists
            .filter { $0.isEnabled }
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: "-")
    }

    // MARK: - Storage

    private func loadFilterLists() {
        guard let data = UserDefaults.standard.data(forKey: filterListsKey),
              let lists = try? JSONDecoder().decode([FilterList].self, from: data) else {
            // Initialize with default lists
            filterLists = FilterList.defaultLists
            saveFilterLists()
            return
        }

        // Merge with default lists (in case new defaults were added)
        var mergedLists = lists
        for defaultList in FilterList.defaultLists {
            if !mergedLists.contains(where: { $0.id == defaultList.id }) {
                mergedLists.append(defaultList)
            }
        }

        filterLists = mergedLists
    }

    private func saveFilterLists() {
        guard let data = try? JSONEncoder().encode(filterLists) else { return }
        UserDefaults.standard.set(data, forKey: filterListsKey)
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)
    }

    private func storeRules(_ rules: [[String: Any]], for filterList: FilterList) throws {
        let rulesFile = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: rules, options: [])
        try data.write(to: rulesFile)
    }

    private func loadRules(for filterList: FilterList) -> [[String: Any]]? {
        let rulesFile = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString).json")

        guard let data = try? Data(contentsOf: rulesFile),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return rules
    }

    // MARK: - Cosmetic & Scriptlet Storage

    private func storeCosmeticFilters(_ filters: ProcessedCosmeticFilters, for filterList: FilterList) {
        let file = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString)-cosmetic.json")
        if let data = try? JSONEncoder().encode(filters) {
            try? data.write(to: file)
        }
    }

    private func storeScriptletRules(_ rules: [ScriptletRule], for filterList: FilterList) {
        let file = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString)-scriptlets.json")
        if let data = try? JSONEncoder().encode(rules) {
            try? data.write(to: file)
        }
    }

    func loadCosmeticFilters(for filterList: FilterList) -> ProcessedCosmeticFilters? {
        // Check in-memory cache first
        if let cached = cosmeticFilters[filterList.id] { return cached }

        // Fall back to disk
        let file = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString)-cosmetic.json")
        guard let data = try? Data(contentsOf: file),
              let filters = try? JSONDecoder().decode(ProcessedCosmeticFilters.self, from: data) else {
            return nil
        }
        cosmeticFilters[filterList.id] = filters
        return filters
    }

    func loadScriptletRules(for filterList: FilterList) -> [ScriptletRule]? {
        // Check in-memory cache first
        if let cached = scriptletRules[filterList.id] { return cached }

        // Fall back to disk
        let file = rulesDirectory.appendingPathComponent("\(filterList.id.uuidString)-scriptlets.json")
        guard let data = try? Data(contentsOf: file),
              let rules = try? JSONDecoder().decode([ScriptletRule].self, from: data) else {
            return nil
        }
        scriptletRules[filterList.id] = rules
        return rules
    }

    /// Get merged cosmetic filters from all enabled filter lists
    func getMergedCosmeticFilters() async -> ProcessedCosmeticFilters {
        var allFilters: [ProcessedCosmeticFilters] = []
        for filterList in filterLists where filterList.isEnabled {
            if let filters = loadCosmeticFilters(for: filterList) {
                allFilters.append(filters)
            }
        }
        let processor = CosmeticFilterListProcessor()
        return await processor.merge(allFilters)
    }

    /// Get all scriptlet rules from enabled filter lists
    func getAllScriptletRules() -> [ScriptletRule] {
        var allRules: [ScriptletRule] = []
        for filterList in filterLists where filterList.isEnabled {
            if let rules = loadScriptletRules(for: filterList) {
                allRules.append(contentsOf: rules)
            }
        }
        return allRules
    }

    // MARK: - Notifications

    private func notifyRulesChanged() {
        NotificationCenter.default.post(name: .filterListsChanged, object: nil)
    }
}

// MARK: - Helper Properties

extension FilterListManager {

    /// Total number of rules from all enabled filter lists
    var totalEnabledRuleCount: Int {
        filterLists.filter { $0.isEnabled }.reduce(0) { $0 + $1.ruleCount }
    }

    /// Number of enabled filter lists
    var enabledCount: Int {
        filterLists.filter { $0.isEnabled }.count
    }

    /// Whether any filter list needs updating
    var needsUpdate: Bool {
        filterLists.contains { list in
            list.isEnabled && (list.lastUpdated == nil || list.ruleCount == 0)
        }
    }

    /// Filter lists that have errors
    var listsWithErrors: [FilterList] {
        filterLists.filter { $0.lastError != nil }
    }

    /// Clear all stored rules to force re-conversion
    func clearStoredRules() {
        // Remove all rule files
        if let files = try? FileManager.default.contentsOfDirectory(at: rulesDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Reset checksums to force re-download
        for index in filterLists.indices {
            filterLists[index].checksum = nil
            filterLists[index].ruleCount = 0
            filterLists[index].lastUpdated = nil
        }

        saveFilterLists()
    }
}
