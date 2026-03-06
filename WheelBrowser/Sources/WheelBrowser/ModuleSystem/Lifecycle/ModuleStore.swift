import Foundation
import AppKit

/// Manages the collection of all installed modules.
/// Handles CRUD, persistence, lifecycle, and notifications for module changes.
@Observable
@MainActor
final class ModuleStore {
    private(set) var modules: [ModuleInstance] = []

    @ObservationIgnored private nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var activationObserver: NSObjectProtocol?

    private static let storeDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WheelBrowser/modules")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        loadFromDisk()
        startScheduleLoop()
        observeAppActivation()
    }

    deinit {
        refreshTask?.cancel()
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CRUD

    /// Install a new module from a validated manifest.
    func install(_ manifest: ModuleManifest) {
        let instance = ModuleInstance(manifest: manifest)
        modules.append(instance)
        saveToDisk(manifest)
        NotificationCenter.default.post(name: .moduleInstalled, object: nil, userInfo: ["moduleId": manifest.id])
    }

    /// Update an existing module with a new manifest (edit-in-place).
    func update(_ manifest: ModuleManifest) {
        guard let index = modules.firstIndex(where: { $0.id == manifest.id }) else { return }
        var updated = manifest
        updated.version = modules[index].manifest.version + 1
        updated.updatedAt = Date()
        modules[index].manifest = updated
        saveToDisk(updated)
        NotificationCenter.default.post(name: .moduleUpdated, object: nil, userInfo: ["moduleId": updated.id])
    }

    /// Remove a module by ID.
    func remove(id: UUID) {
        modules.removeAll { $0.id == id }
        deleteFromDisk(id: id)
        NotificationCenter.default.post(name: .moduleRemoved, object: nil, userInfo: ["moduleId": id])
    }

    /// Toggle a module's enabled state.
    func toggleEnabled(id: UUID) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[index].manifest.isEnabled.toggle()
        saveToDisk(modules[index].manifest)
        let name: Notification.Name = modules[index].manifest.isEnabled ? .moduleEnabled : .moduleDisabled
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["moduleId": id])
    }

    // MARK: - Queries

    /// All enabled modules of a given type.
    func enabledModules(ofType type: ModuleType) -> [ModuleInstance] {
        modules.filter { $0.manifest.isEnabled && $0.manifest.moduleType == type }
    }

    /// All enabled modules that match a given URL.
    func modulesMatching(url: URL) -> [ModuleInstance] {
        modules.filter { instance in
            guard instance.manifest.isEnabled else { return false }
            return instance.manifest.triggers.contains { trigger in
                switch trigger.type {
                case .pageLoad:
                    return urlMatches(url: url, pattern: trigger.urlPattern ?? "*")
                case .always:
                    return true
                default:
                    return false
                }
            }
        }
    }

    /// All enabled modules with manual trigger (potential LLM tools).
    func manualModules() -> [ModuleInstance] {
        modules.filter { instance in
            instance.manifest.isEnabled &&
            instance.manifest.triggers.contains(where: { $0.type == .manual })
        }
    }

    /// All enabled modules with scheduled triggers.
    func scheduledModules() -> [ModuleInstance] {
        modules.filter { instance in
            instance.manifest.isEnabled &&
            instance.manifest.triggers.contains(where: { $0.type == .schedule })
        }
    }

    /// Find a module by ID.
    func module(withId id: UUID) -> ModuleInstance? {
        modules.first(where: { $0.id == id })
    }

    // MARK: - URL Pattern Matching

    private func urlMatches(url: URL, pattern: String) -> Bool {
        if pattern == "*" { return true }

        let host = url.host ?? ""
        let path = url.path

        // Simple wildcard matching: "*://*.example.com/*"
        let cleanPattern = pattern
            .replacingOccurrences(of: "*://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        let parts = cleanPattern.split(separator: "/", maxSplits: 1)
        let hostPattern = String(parts.first ?? "")
        let pathPattern = parts.count > 1 ? "/" + String(parts[1]) : "/*"

        // Host matching
        let hostMatch: Bool
        if hostPattern == "*" {
            hostMatch = true
        } else if hostPattern.hasPrefix("*.") {
            let suffix = String(hostPattern.dropFirst(2))
            hostMatch = host == suffix || host.hasSuffix("." + suffix)
        } else {
            hostMatch = host == hostPattern
        }

        // Path matching
        let pathMatch: Bool
        if pathPattern == "/*" {
            pathMatch = true
        } else {
            pathMatch = path.hasPrefix(pathPattern.replacingOccurrences(of: "*", with: ""))
        }

        return hostMatch && pathMatch
    }

    // MARK: - Persistence

    private func saveToDisk(_ manifest: ModuleManifest) {
        let fileURL = Self.storeDir.appendingPathComponent("\(manifest.id.uuidString).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.Widgets.error("Failed to save module '\(manifest.name)'", error: error)
        }
    }

    private func deleteFromDisk(id: UUID) {
        let fileURL = Self.storeDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loadFromDisk() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.storeDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let manifest = try decoder.decode(ModuleManifest.self, from: data)
                modules.append(ModuleInstance(manifest: manifest))
            } catch {
                Log.Widgets.error("Failed to load module from \(file.lastPathComponent)", error: error)
            }
        }

        modules.sort { $0.manifest.createdAt < $1.manifest.createdAt }
    }

    // MARK: - Scheduled Refresh

    private func startScheduleLoop() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s polling
                guard let self else { return }
                for module in self.scheduledModules() where module.isStale {
                    NotificationCenter.default.post(
                        name: .moduleScheduledRefresh,
                        object: nil,
                        userInfo: ["moduleId": module.id]
                    )
                }
            }
        }
    }

    private func observeAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for module in self.scheduledModules() where module.isStale {
                    NotificationCenter.default.post(
                        name: .moduleScheduledRefresh,
                        object: nil,
                        userInfo: ["moduleId": module.id]
                    )
                }
            }
        }
    }
}

// MARK: - Module Instance

/// Runtime representation of an installed module.
@Observable
@MainActor
final class ModuleInstance: Identifiable {
    let id: UUID
    var manifest: ModuleManifest
    var lastData: RenderInput?
    var lastExecuted: Date?
    var isLoading: Bool = false
    var error: String?

    init(manifest: ModuleManifest) {
        self.id = manifest.id
        self.manifest = manifest
    }

    /// Whether this module is stale and should be refreshed (for scheduled modules).
    var isStale: Bool {
        guard let interval = manifest.triggers.compactMap({ $0.intervalSeconds }).first else {
            return false
        }
        guard let lastExecuted else { return true }
        return Date().timeIntervalSince(lastExecuted) >= Double(interval)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let moduleInstalled = Notification.Name("moduleInstalled")
    static let moduleUpdated = Notification.Name("moduleUpdated")
    static let moduleRemoved = Notification.Name("moduleRemoved")
    static let moduleEnabled = Notification.Name("moduleEnabled")
    static let moduleDisabled = Notification.Name("moduleDisabled")
    static let moduleScheduledRefresh = Notification.Name("moduleScheduledRefresh")
}
