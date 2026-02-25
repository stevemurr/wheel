import Foundation

/// Utilities for calculating widget layout parameters based on size.
///
/// This module provides standardized calculations for item limits, column counts,
/// and spacing that should be consistent across all widgets. Using these helpers
/// ensures visual consistency and reduces code duplication.
///
/// Usage:
/// ```swift
/// let limit = WidgetLayout.itemLimit(for: .medium) // 4
/// let columns = WidgetLayout.columnCount(for: .large) // 2
/// ```
enum WidgetLayout {
    // MARK: - Item Limits

    /// Returns the maximum number of items to display for a given widget size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Maximum item count
    static func itemLimit(for size: WidgetSize) -> Int {
        switch size {
        case .small:
            return 2
        case .medium:
            return 4
        case .large:
            return 8
        case .wide:
            return 6
        case .extraLarge:
            return 12
        }
    }

    /// Returns the maximum number of items for a grid layout at the given size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Maximum grid item count
    static func gridItemLimit(for size: WidgetSize) -> Int {
        switch size {
        case .small:
            return 4   // 2x2
        case .medium:
            return 4   // 4x1 or 2x2
        case .large:
            return 8   // 4x2 or 2x4
        case .wide:
            return 8   // 8x1 or 4x2
        case .extraLarge:
            return 16  // 8x2 or 4x4
        }
    }

    // MARK: - Column Counts

    /// Returns the recommended number of columns for a list or grid at the given size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Number of columns
    static func columnCount(for size: WidgetSize) -> Int {
        switch size {
        case .small:
            return 1
        case .medium:
            return 2
        case .large:
            return 2
        case .wide:
            return 4
        case .extraLarge:
            return 4
        }
    }

    /// Returns the column count for a grid of icons or thumbnails.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Number of columns
    static func iconGridColumns(for size: WidgetSize) -> Int {
        switch size {
        case .small:
            return 2
        case .medium:
            return 4
        case .large:
            return 4
        case .wide:
            return 8
        case .extraLarge:
            return 8
        }
    }

    // MARK: - Row Counts

    /// Returns the number of visible rows for a list layout.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Number of visible rows
    static func visibleRows(for size: WidgetSize) -> Int {
        switch size {
        case .small:
            return 2
        case .medium:
            return 2
        case .large:
            return 4
        case .wide:
            return 2
        case .extraLarge:
            return 4
        }
    }

    // MARK: - Spacing

    /// Returns the recommended internal padding for a widget.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Padding value
    static func padding(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small:
            return 8
        case .medium:
            return 12
        case .large:
            return 16
        case .wide:
            return 12
        case .extraLarge:
            return 16
        }
    }

    /// Returns the recommended spacing between items.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Spacing value
    static func itemSpacing(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small:
            return 6
        case .medium:
            return 8
        case .large:
            return 10
        case .wide:
            return 8
        case .extraLarge:
            return 12
        }
    }

    // MARK: - Typography

    /// Returns whether the title should be shown for this widget size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: True if title should be shown
    static func shouldShowTitle(for size: WidgetSize) -> Bool {
        return size != .small
    }

    /// Returns the recommended title font size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Font size
    static func titleFontSize(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small:
            return 11
        case .medium:
            return 13
        case .large:
            return 14
        case .wide:
            return 13
        case .extraLarge:
            return 14
        }
    }

    /// Returns the recommended body/content font size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Font size
    static func contentFontSize(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small:
            return 10
        case .medium:
            return 12
        case .large:
            return 13
        case .wide:
            return 12
        case .extraLarge:
            return 13
        }
    }

    // MARK: - Icon Sizes

    /// Returns the recommended icon size for list items.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Icon dimension
    static func iconSize(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small:
            return 16
        case .medium:
            return 20
        case .large:
            return 24
        case .wide:
            return 20
        case .extraLarge:
            return 28
        }
    }

    /// Returns the recommended thumbnail size for grid items.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Thumbnail dimension
    static func thumbnailSize(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small:
            return 36
        case .medium:
            return 44
        case .large:
            return 52
        case .wide:
            return 44
        case .extraLarge:
            return 60
        }
    }

    // MARK: - Convenience

    /// Returns a complete layout configuration for a widget size.
    ///
    /// - Parameter size: The widget size
    /// - Returns: Layout configuration struct
    static func configuration(for size: WidgetSize) -> LayoutConfiguration {
        LayoutConfiguration(
            itemLimit: itemLimit(for: size),
            columnCount: columnCount(for: size),
            visibleRows: visibleRows(for: size),
            padding: padding(for: size),
            itemSpacing: itemSpacing(for: size),
            showTitle: shouldShowTitle(for: size),
            titleFontSize: titleFontSize(for: size),
            contentFontSize: contentFontSize(for: size),
            iconSize: iconSize(for: size)
        )
    }
}

// MARK: - Layout Configuration

/// Complete layout configuration for a widget
struct LayoutConfiguration {
    let itemLimit: Int
    let columnCount: Int
    let visibleRows: Int
    let padding: CGFloat
    let itemSpacing: CGFloat
    let showTitle: Bool
    let titleFontSize: CGFloat
    let contentFontSize: CGFloat
    let iconSize: CGFloat
}
