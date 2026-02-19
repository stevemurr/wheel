import SwiftUI

/// Grid layout for displaying widgets using absolute positioning
struct WidgetGridView: View {
    @ObservedObject var manager: NewTabPageManager
    let containerWidth: CGFloat

    private let spacing: CGFloat = 16
    private let columnCount: Int = 4
    private let cellHeight: CGFloat = 160

    private var cellWidth: CGFloat {
        let totalSpacing = spacing * CGFloat(columnCount + 1)
        return (containerWidth - totalSpacing) / CGFloat(columnCount)
    }

    /// Calculate grid placements for all widgets
    private var gridPlacements: [(widget: AnyWidget, col: Int, row: Int)] {
        var placements: [(widget: AnyWidget, col: Int, row: Int)] = []
        var grid: [[Bool]] = [] // grid[row][col] = occupied

        for widget in manager.widgets {
            let widgetCols = widget.currentSize.gridWidth
            let widgetRows = widget.currentSize.gridHeight

            // Find first available position
            var placed = false
            var searchRow = 0

            while !placed {
                // Ensure grid has enough rows
                while grid.count <= searchRow + widgetRows - 1 {
                    grid.append(Array(repeating: false, count: columnCount))
                }

                // Try each column in this row
                for col in 0...(columnCount - widgetCols) {
                    if canPlace(at: (row: searchRow, col: col), size: (rows: widgetRows, cols: widgetCols), in: grid) {
                        // Place widget
                        placements.append((widget: widget, col: col, row: searchRow))

                        // Mark cells as occupied
                        for r in searchRow..<(searchRow + widgetRows) {
                            for c in col..<(col + widgetCols) {
                                grid[r][c] = true
                            }
                        }
                        placed = true
                        break
                    }
                }

                if !placed {
                    searchRow += 1
                }
            }
        }

        return placements
    }

    private func canPlace(at position: (row: Int, col: Int), size: (rows: Int, cols: Int), in grid: [[Bool]]) -> Bool {
        for r in position.row..<(position.row + size.rows) {
            for c in position.col..<(position.col + size.cols) {
                if r >= grid.count || c >= columnCount || grid[r][c] {
                    return false
                }
            }
        }
        return true
    }

    /// Calculate total grid height
    private var totalGridHeight: CGFloat {
        let placements = gridPlacements
        guard !placements.isEmpty else { return 0 }

        var maxRow = 0
        for placement in placements {
            let widgetEndRow = placement.row + placement.widget.currentSize.gridHeight
            maxRow = max(maxRow, widgetEndRow)
        }

        return CGFloat(maxRow) * cellHeight + CGFloat(maxRow - 1) * spacing
    }

    var body: some View {
        let placements = gridPlacements

        ZStack(alignment: .topLeading) {
            // Invisible spacer to establish the grid size
            Color.clear
                .frame(height: totalGridHeight)

            ForEach(placements, id: \.widget.id) { placement in
                let xOffset = spacing + CGFloat(placement.col) * (cellWidth + spacing)
                let yOffset = CGFloat(placement.row) * (cellHeight + spacing)

                WidgetContainerView(
                    widget: placement.widget,
                    isEditMode: manager.isEditMode,
                    onRemove: {
                        withAnimation(.spring(response: 0.3)) {
                            manager.removeWidget(id: placement.widget.id)
                        }
                    },
                    onSizeChange: { newSize in
                        withAnimation(.spring(response: 0.3)) {
                            manager.updateWidgetSize(id: placement.widget.id, size: newSize)
                        }
                    }
                )
                .frame(
                    width: widgetWidth(for: placement.widget.currentSize),
                    height: widgetHeight(for: placement.widget.currentSize)
                )
                .offset(x: xOffset, y: yOffset)
            }
        }
        .frame(height: totalGridHeight)
        .padding(.horizontal, spacing)
    }

    private func widgetWidth(for size: WidgetSize) -> CGFloat {
        let gridWidth = size.gridWidth
        return cellWidth * CGFloat(gridWidth) + spacing * CGFloat(gridWidth - 1)
    }

    private func widgetHeight(for size: WidgetSize) -> CGFloat {
        let gridHeight = size.gridHeight
        return cellHeight * CGFloat(gridHeight) + spacing * CGFloat(gridHeight - 1)
    }
}
