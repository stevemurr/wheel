import SwiftUI

/// Size options for widgets in the new tab page grid
enum WidgetSize: String, Codable, CaseIterable {
    case small      // 1x1
    case medium     // 2x1
    case large      // 2x2
    case wide       // 4x1
    case extraLarge // 4x2

    var gridWidth: Int {
        switch self {
        case .small: return 1
        case .medium: return 2
        case .large: return 2
        case .wide: return 4
        case .extraLarge: return 4
        }
    }

    var gridHeight: Int {
        switch self {
        case .small: return 1
        case .medium: return 1
        case .large: return 2
        case .wide: return 1
        case .extraLarge: return 2
        }
    }

    var displayName: String {
        switch self {
        case .small: return "Small (1×1)"
        case .medium: return "Medium (2×1)"
        case .large: return "Large (2×2)"
        case .wide: return "Wide (4×1)"
        case .extraLarge: return "Extra Large (4×2)"
        }
    }
}

/// Protocol for all widgets displayed on the new tab page
@MainActor
protocol Widget: Identifiable, ObservableObject {
    /// Unique identifier for this widget type (used for serialization)
    static var typeIdentifier: String { get }

    /// Display name shown in the widget gallery
    static var displayName: String { get }

    /// Icon name (SF Symbol) for the widget
    static var iconName: String { get }

    /// Instance identifier
    var id: UUID { get }

    /// Sizes this widget supports
    var supportedSizes: [WidgetSize] { get }

    /// Current size of the widget
    var currentSize: WidgetSize { get set }

    /// Creates the widget's content view
    associatedtype ContentView: View
    @ViewBuilder func makeContent() -> ContentView

    /// Refreshes the widget's data
    func refresh() async

    /// Encodes widget-specific configuration data
    func encodeConfiguration() -> [String: Any]

    /// Decodes widget-specific configuration data
    func decodeConfiguration(_ data: [String: Any])
}

/// Default implementations
extension Widget {
    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large]
    }

    func encodeConfiguration() -> [String: Any] {
        [:]
    }

    func decodeConfiguration(_ data: [String: Any]) {
        // Default: no-op
    }
}
