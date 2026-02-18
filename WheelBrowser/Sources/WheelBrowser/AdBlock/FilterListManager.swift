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

    /// Storage keys
    private let filterListsKey = "FilterListSubscriptions"
    private let rulesDirectoryName = "FilterLists"
    private let converterVersionKey = "FilterListConverterVersion"

    /// Current converter version - increment when converter logic changes
    private let currentConverterVersion = 3

    /// Directory for storing converted rules
    private var rulesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser")
        return appDir.appendingPathComponent(rulesDirectoryName)
    }

    private init() {
        loadFilterLists()
        ensureDirectoryExists()
        checkConverterVersion()
    }

    /// Check if converter version changed and clear rules if needed
    private func checkConverterVersion() {
        let storedVersion = UserDefaults.standard.integer(forKey: converterVersionKey)
        if storedVersion != currentConverterVersion {
            print("FilterListManager: Converter version changed (\(storedVersion) -> \(currentConverterVersion)), clearing stored rules")
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

    /// Update all enabled filter lists
    func updateAll(forceUpdate: Bool = false) async {
        guard !isUpdating else { return }

        isUpdating = true
        updateProgress = 0
        lastError = nil

        let enabledLists = filterLists.filter { $0.isEnabled }
        var hasChanges = false

        for (index, filterList) in enabledLists.enumerated() {
            do {
                let updated = try await updateFilterList(filterList, forceUpdate: forceUpdate)
                if updated {
                    hasChanges = true
                }
            } catch {
                // Record error but continue with other lists
                if let listIndex = filterLists.firstIndex(where: { $0.id == filterList.id }) {
                    filterLists[listIndex].lastError = error.localizedDescription
                }
                print("FilterListManager: Failed to update \(filterList.name): \(error)")
            }

            updateProgress = Double(index + 1) / Double(enabledLists.count)
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
