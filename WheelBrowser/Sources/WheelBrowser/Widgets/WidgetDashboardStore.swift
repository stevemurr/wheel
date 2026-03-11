import AppKit
import Foundation

@Observable
@MainActor
final class WidgetDashboardStore {
    private(set) var records: [WidgetRecord] = []
    var isEditing: Bool = false
    private(set) var pendingRefreshIDs: [UUID] = []

    @ObservationIgnored private nonisolated(unsafe) var activationObserver: NSObjectProtocol?
    @ObservationIgnored private let store: JSONBackedStore<[WidgetRecord]>
    @ObservationIgnored private let legacyCleanupPaths: [URL]

    private static let storePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WheelBrowser")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("widget_dashboard.json")
    }()

    private static let legacyWidgetPath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WheelBrowser/pipeline_widgets.json")
    }()

    private static let legacyModulesPath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WheelBrowser/modules")
    }()

    private static let legacyModuleStoragePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WheelBrowser/module_storage")
    }()

    init(
        storageURL: URL? = nil,
        legacyCleanupPaths: [URL]? = nil,
        observeActivation: Bool = true
    ) {
        let resolvedStorageURL = storageURL ?? Self.storePath
        self.store = JSONBackedStore(
            backend: FileSystemStoreBackend(rootURL: resolvedStorageURL.deletingLastPathComponent()),
            key: StoreKey(resolvedStorageURL.lastPathComponent),
            codingConfiguration: .prettyPrintedSortedKeys
        )
        self.legacyCleanupPaths = legacyCleanupPaths ?? [
            Self.legacyWidgetPath,
            Self.legacyModulesPath,
            Self.legacyModuleStoragePath,
        ]
        hardResetLegacyState()
        load()
        if observeActivation {
            observeAppActivation()
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    var manifests: [WidgetManifest] {
        records
            .sorted { $0.position < $1.position }
            .map(\.manifest)
    }

    func load() {
        do {
            let decoded = try store.load() ?? []
            var repairedExistingWidgets = false
            let repaired = decoded.map { record -> WidgetRecord in
                let result = WidgetManifestRepair.repair(record.manifest)
                repairedExistingWidgets = repairedExistingWidgets || result.changed

                var updated = record
                updated.manifest = result.manifest
                return updated
            }

            records = repaired.sorted { $0.position < $1.position }
            reindex()
            if repairedExistingWidgets {
                persistIgnoringErrors()
            }
        } catch {
            records = []
            Log.Widgets.error("Failed to load widget dashboard", error: error)
        }
    }

    func add(manifest: WidgetManifest) throws {
        let validated = try WidgetManifestValidator.validate(manifest)
        records.append(
            WidgetRecord(
                manifest: validated,
                position: records.count,
                lastAttemptedAt: nil,
                lastLoadedAt: nil,
                lastError: nil
            )
        )

        do {
            try save()
            refresh(id: validated.id)
        } catch {
            records.removeAll { $0.id == validated.id }
            reindex()
            Log.Widgets.error("Failed to add widget", error: error)
            throw error
        }
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        reindex()
        pendingRefreshIDs.removeAll { $0 == id }
        persistIgnoringErrors()
    }

    func move(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0,
              source < records.count,
              destination >= 0,
              destination < records.count else {
            return
        }

        let record = records.remove(at: source)
        records.insert(record, at: destination)
        reindex()
        persistIgnoringErrors()
    }

    func refresh(id: UUID) {
        if !pendingRefreshIDs.contains(id) {
            pendingRefreshIDs.append(id)
        }
    }

    func toggleLayoutPreference(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        switch records[index].layoutPreference {
        case .auto:
            records[index].layoutPreference = .singleColumn
        case .singleColumn:
            records[index].layoutPreference = .fullWidth
        case .fullWidth:
            records[index].layoutPreference = .auto
        }
        persistIgnoringErrors()
    }

    func toggleVisualizationPreference(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard records[index].manifest.widgetType == .lineChart else { return }

        switch records[index].visualizationPreference {
        case .auto:
            records[index].visualizationPreference = .value
        case .value:
            records[index].visualizationPreference = .lineChart
        case .lineChart:
            records[index].visualizationPreference = .value
        }

        persistIgnoringErrors()
    }

    func refreshStale() {
        for record in records where isStale(record) {
            refresh(id: record.id)
        }
    }

    func markLoaded(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].lastAttemptedAt = Date()
        records[index].lastLoadedAt = Date()
        records[index].lastError = nil
        pendingRefreshIDs.removeAll { $0 == id }
        persistIgnoringErrors()
    }

    func markError(id: UUID, message: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].lastAttemptedAt = Date()
        records[index].lastError = message
        pendingRefreshIDs.removeAll { $0 == id }
        persistIgnoringErrors()
    }

    func consumePendingRefreshes(_ ids: [UUID]) {
        let consumed = Set(ids)
        pendingRefreshIDs.removeAll { consumed.contains($0) }
    }

    func index(of id: UUID) -> Int? {
        records.firstIndex { $0.id == id }
    }

    private func isStale(_ record: WidgetRecord) -> Bool {
        if record.manifest.ttl == 0 {
            return false
        }
        guard let lastAttemptedAt = record.lastAttemptedAt ?? record.lastLoadedAt else {
            return true
        }
        return Date().timeIntervalSince(lastAttemptedAt) >= TimeInterval(record.manifest.ttl)
    }

    private func save() throws {
        try store.save(records)
    }

    private func persistIgnoringErrors() {
        do {
            try save()
        } catch {
            Log.Widgets.error("Failed to save widget dashboard", error: error)
        }
    }

    private func reindex() {
        for (index, _) in records.enumerated() {
            records[index].position = index
            if records[index].lastError?.isEmpty == true {
                records[index].lastError = nil
            }
        }
    }

    private func hardResetLegacyState() {
        let fileManager = FileManager.default
        for path in legacyCleanupPaths where fileManager.fileExists(atPath: path.path) {
            try? fileManager.removeItem(at: path)
        }
    }

    private func observeAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier == Bundle.main.bundleIdentifier else {
                return
            }
            Task { @MainActor [weak self] in
                self?.refreshStale()
            }
        }
    }
}
