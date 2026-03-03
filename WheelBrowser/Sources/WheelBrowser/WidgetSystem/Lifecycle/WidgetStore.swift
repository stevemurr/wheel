import Foundation
import AppKit

/// Manages the collection of widget instances on the new tab page.
/// Handles CRUD, persistence, and automatic refresh scheduling.
@Observable
@MainActor
final class WidgetStore {
    private(set) var widgets: [WidgetInstance] = []
    var isEditMode: Bool = false

    private let registry: SkillRegistry
    private let executor: PipelineExecutor
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var activationObserver: NSObjectProtocol?

    private static let storePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WheelBrowser")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pipeline_widgets.json")
    }()

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(registry: SkillRegistry? = nil) {
        let reg = registry ?? SkillRegistry.createDefault()
        self.registry = reg
        self.executor = PipelineExecutor(registry: reg)
        loadFromDisk()
        startRefreshLoop()
        observeAppActivation()
    }

    deinit {
        refreshTask?.cancel()
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CRUD

    func addWidget(spec: WidgetPipelineSpec) {
        let instance = WidgetInstance(spec: spec, executor: executor)
        widgets.append(instance)
        save()
        Task { @MainActor in await instance.refresh() }
    }

    func removeWidget(id: UUID) {
        widgets.removeAll { $0.id == id }
        save()
    }

    func moveWidget(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func refreshAll() {
        let staleWidgets = widgets.filter(\.isStale)
        guard !staleWidgets.isEmpty else { return }

        Task { @MainActor in
            // Use TaskGroup to bound concurrency and ensure cancellation propagation
            await withTaskGroup(of: Void.self) { group in
                for widget in staleWidgets {
                    group.addTask { @MainActor in
                        await widget.refresh()
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        // Snapshot the data on MainActor, then write to disk off the main thread
        let persisted = widgets.enumerated().map { idx, instance in
            PersistedWidget(spec: instance.spec, position: idx)
        }

        Task.detached(priority: .utility) {
            do {
                let data = try Self.encoder.encode(persisted)
                try data.write(to: Self.storePath, options: .atomic)
            } catch {
                Log.Widgets.error("Failed to save widgets", error: error)
            }
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: Self.storePath.path) else { return }

        do {
            let data = try Data(contentsOf: Self.storePath)
            let persisted = try Self.decoder.decode([PersistedWidget].self, from: data)

            widgets = persisted
                .sorted { $0.position < $1.position }
                .map { WidgetInstance(spec: $0.spec, executor: executor) }
        } catch {
            Log.Widgets.error("Failed to load widgets", error: error)
        }
    }

    // MARK: - Refresh Scheduling

    private func startRefreshLoop() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60s polling
                } catch {
                    break // Task was cancelled during sleep
                }

                guard let self else { return }
                // Snapshot stale widgets on MainActor before iterating
                let staleWidgets = await MainActor.run { self.widgets.filter(\.isStale) }

                // Stagger refreshes
                for widget in staleWidgets {
                    guard !Task.isCancelled else { break }
                    await widget.refresh()
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s stagger
                    } catch {
                        break // Task was cancelled during stagger sleep
                    }
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
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else {
                return
            }
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
    }
}
