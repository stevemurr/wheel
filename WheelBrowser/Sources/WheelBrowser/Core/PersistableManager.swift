import Foundation

/// Protocol for managers that persist data to the file system.
///
/// Conforming types implement a consistent save/load/reset pattern with
/// automatic directory creation and error handling. This ensures data
/// persistence behavior is standardized across the application.
///
/// Usage:
/// ```swift
/// class MyManager: PersistableManager {
///     static var persistenceFileName: String { "my_data.json" }
///     typealias PersistenceData = MyData
///
///     private(set) var data: MyData = .default
///
///     func load() async {
///         data = await loadFromDisk() ?? .default
///     }
///
///     func save() async {
///         await saveToDisk(data)
///     }
/// }
/// ```
@MainActor
protocol PersistableManager: AnyObject {
    /// The type of data being persisted (must be Codable)
    associatedtype PersistenceData: Codable

    /// File name for persistence (e.g., "workspaces.json")
    static var persistenceFileName: String { get }

    /// Loads data from disk
    func load() async

    /// Saves current data to disk
    func save() async

    /// Resets to default state
    func reset() async
}

// MARK: - Default Implementations

extension PersistableManager {
    /// Directory URL for app support files
    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)
    }

    /// Full URL for the persistence file
    static var persistenceFileURL: URL {
        appSupportDirectory.appendingPathComponent(persistenceFileName)
    }

    /// Creates the app support directory if needed
    func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: Self.appSupportDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Loads data from disk with error handling
    /// Returns nil if file doesn't exist or decoding fails
    func loadFromDisk() async -> PersistenceData? {
        ensureDirectoryExists()

        guard FileManager.default.fileExists(atPath: Self.persistenceFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: Self.persistenceFileURL)
            let decoded = try JSONDecoder().decode(PersistenceData.self, from: data)
            return decoded
        } catch {
            Log.Core.error("Failed to load \(Self.persistenceFileName)", error: error)
            return nil
        }
    }

    /// Saves data to disk with atomic write
    func saveToDisk(_ data: PersistenceData) async {
        ensureDirectoryExists()

        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: Self.persistenceFileURL, options: .atomic)
        } catch {
            Log.Core.error("Failed to save \(Self.persistenceFileName)", error: error)
        }
    }

    /// Deletes the persistence file
    func deleteFromDisk() {
        try? FileManager.default.removeItem(at: Self.persistenceFileURL)
    }
}

// MARK: - Observable Persistence

/// Protocol for ObservableObject managers that debounce saves
@MainActor
protocol DebouncedPersistableManager: PersistableManager {
    /// Task for debounced saving
    var saveTask: Task<Void, Never>? { get set }

    /// Delay before saving (defaults to 500ms)
    var saveDebounceInterval: UInt64 { get }
}

extension DebouncedPersistableManager {
    var saveDebounceInterval: UInt64 { 500_000_000 } // 500ms in nanoseconds

    /// Schedules a debounced save operation
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceInterval)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    /// Saves immediately, canceling any pending debounced save
    func saveImmediately() async {
        saveTask?.cancel()
        saveTask = nil
        await save()
    }
}
