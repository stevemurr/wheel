import Foundation

/// Registry for available widget types
@MainActor
final class WidgetRegistry {
    static let shared = WidgetRegistry()

    /// Factory closure type for creating widgets
    typealias WidgetFactory = () -> any Widget

    /// Registered widget types
    private var factories: [String: WidgetFactory] = [:]

    /// Metadata for each widget type
    private var metadata: [String: WidgetMetadata] = [:]

    struct WidgetMetadata {
        let typeIdentifier: String
        let displayName: String
        let iconName: String
        let defaultSize: WidgetSize
    }

    private init() {
        registerBuiltInWidgets()
    }

    /// Register a widget type
    func register<W: Widget>(
        _ widgetType: W.Type,
        factory: @escaping () -> W
    ) {
        let typeId = W.typeIdentifier
        factories[typeId] = factory
        metadata[typeId] = WidgetMetadata(
            typeIdentifier: typeId,
            displayName: W.displayName,
            iconName: W.iconName,
            defaultSize: .medium
        )
    }

    /// Create a widget instance from its type identifier
    func createWidget(typeIdentifier: String) -> (any Widget)? {
        factories[typeIdentifier]?()
    }

    /// Get all available widget types
    var availableWidgets: [WidgetMetadata] {
        Array(metadata.values).sorted { $0.displayName < $1.displayName }
    }

    /// Check if a widget type is registered
    func isRegistered(_ typeIdentifier: String) -> Bool {
        factories[typeIdentifier] != nil
    }

    // MARK: - Built-in Widgets

    private func registerBuiltInWidgets() {
        register(SearchWidget.self) { SearchWidget() }
        register(QuickLinksWidget.self) { QuickLinksWidget() }
        register(RecentHistoryWidget.self) { RecentHistoryWidget() }
        register(ClockWidget.self) { ClockWidget() }
        register(CalendarWidget.self) { CalendarWidget() }
        register(ShortcutsWidget.self) { ShortcutsWidget() }
        register(QuickNoteWidget.self) { QuickNoteWidget() }
        register(DailyNotesWidget.self) { DailyNotesWidget() }
        register(AIWidget.self) { AIWidget(config: .placeholder) }
    }
}
