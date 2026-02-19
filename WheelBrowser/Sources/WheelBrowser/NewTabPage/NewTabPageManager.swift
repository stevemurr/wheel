import Foundation
import Combine

/// Manages new tab page state and persistence
@MainActor
final class NewTabPageManager: ObservableObject {
    static let shared = NewTabPageManager()

    @Published var config: NewTabPageConfig
    @Published var widgets: [AnyWidget] = []
    @Published var isEditMode: Bool = false

    private let configFileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configFileURL = appDir.appendingPathComponent("newtab_widgets.json")

        // Load saved config or use default
        if let data = try? Data(contentsOf: configFileURL),
           let savedConfig = try? JSONDecoder().decode(NewTabPageConfig.self, from: data) {
            config = savedConfig
        } else {
            config = .defaultConfig
        }

        loadWidgets()
    }

    /// Load widget instances from configuration
    func loadWidgets() {
        widgets = config.widgets.compactMap { widgetConfig in
            guard let widget = WidgetRegistry.shared.createWidget(typeIdentifier: widgetConfig.typeIdentifier) else {
                return nil
            }

            // Apply saved size
            widget.currentSize = widgetConfig.size

            // Apply custom data
            let customData = widgetConfig.customData.mapValues { $0.value }
            widget.decodeConfiguration(customData)

            return AnyWidget(widget)
        }
    }

    /// Save current configuration to disk
    func save() {
        // Update config with current widget states
        config.widgets = widgets.enumerated().map { index, widget in
            let customData = widget.encodeConfiguration().mapValues { AnyCodable($0) }
            return WidgetInstanceConfig(
                id: widget.id,
                typeIdentifier: widget.typeIdentifier,
                size: widget.currentSize,
                position: index,
                customData: customData
            )
        }

        // Persist to disk
        Task {
            do {
                let data = try JSONEncoder().encode(config)
                try data.write(to: configFileURL, options: .atomic)
            } catch {
                print("Failed to save new tab page config: \(error)")
            }
        }
    }

    /// Add a new widget
    func addWidget(typeIdentifier: String) {
        guard let widget = WidgetRegistry.shared.createWidget(typeIdentifier: typeIdentifier) else {
            return
        }

        widgets.append(AnyWidget(widget))
        save()
    }

    /// Remove a widget
    func removeWidget(id: UUID) {
        widgets.removeAll { $0.id == id }
        save()
    }

    /// Move a widget to a new position
    func moveWidget(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Update a widget's size
    func updateWidgetSize(id: UUID, size: WidgetSize) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].currentSize = size
            save()
        }
    }

    /// Refresh all widgets
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for widget in widgets {
                group.addTask {
                    await widget.refresh()
                }
            }
        }
    }

    /// Reset to default configuration
    func resetToDefaults() {
        config = .defaultConfig
        loadWidgets()
        save()
    }
}
