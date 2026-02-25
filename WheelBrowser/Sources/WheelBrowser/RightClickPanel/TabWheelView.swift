import SwiftUI

struct TabWheelView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var wheelState: TabWheelState
    @ObservedObject var screenshotManager = TabScreenshotManager.shared
    let onSelectTab: (UUID) -> Void
    let onDismiss: () -> Void

    /// Cached sorted tabs by depth to avoid recalculating on every frame
    @State private var cachedSortedTabs: [TabWithIndex] = []
    @State private var lastRotationAngle: Double = 0
    @State private var lastTabCount: Int = 0

    // Dynamic radius based on tab count
    private var radius: CGFloat {
        let count = browserState.tabs.count
        if count <= 4 {
            return 130
        } else if count <= 8 {
            return 160
        } else {
            return min(200, 130 + CGFloat(count - 4) * 10)
        }
    }

    // Base item size (will be scaled by position)
    private var baseItemSize: CGFloat {
        let count = browserState.tabs.count
        if count <= 4 {
            return 80
        } else if count <= 8 {
            return 70
        } else {
            return max(55, 80 - CGFloat(count - 4) * 3)
        }
    }

    private var totalSize: CGFloat {
        radius * 2 + baseItemSize * 1.8 + 60
    }

    /// Get sorted tabs, using cache when rotation hasn't changed significantly
    private var sortedTabs: [TabWithIndex] {
        // Only recalculate if rotation changed significantly (more than 5 degrees) or tab count changed
        // Increased threshold from 1 to 5 degrees to reduce sort frequency during animations
        let rotationChanged = abs(wheelState.rotationAngle - lastRotationAngle) > 5.0
        let tabCountChanged = browserState.tabs.count != lastTabCount

        if !rotationChanged && !tabCountChanged && !cachedSortedTabs.isEmpty {
            return cachedSortedTabs
        }
        return sortedTabsByDepth()
    }

    var body: some View {
        ZStack {
            // Tab items arranged in a circle, sorted by depth (back to front)
            ForEach(sortedTabs, id: \.tab.id) { item in
                let angle = angleForTab(at: item.index)
                let scale = scaleForAngle(angle)
                let adjustedRadius = radiusForScale(scale)
                let position = positionForAngle(angle, radius: adjustedRadius)

                TabWheelItem(
                    tab: item.tab,
                    isSelected: item.index == wheelState.selectedIndex,
                    size: baseItemSize,
                    scale: scale,
                    screenshotManager: screenshotManager
                )
                .position(x: totalSize / 2 + position.x, y: totalSize / 2 + position.y)
                .zIndex(scale * 100) // Higher scale = closer to front
                .onTapGesture {
                    selectTab(item.tab)
                }
            }

        }
        .frame(width: totalSize, height: totalSize)
        .onChange(of: wheelState.rotationAngle) { _, _ in
            updateCacheIfNeeded()
        }
        .onChange(of: browserState.tabs.count) { _, _ in
            updateCacheIfNeeded()
        }
        .onAppear {
            updateCacheIfNeeded()
        }
    }

    // MARK: - Depth Sorting

    struct TabWithIndex {
        let tab: Tab
        let index: Int
    }

    /// Sort tabs by their visual depth (back to front) so items closer to bottom render first
    private func sortedTabsByDepth() -> [TabWithIndex] {
        let items = browserState.tabs.enumerated().map { TabWithIndex(tab: $1, index: $0) }
        return items.sorted { item1, item2 in
            let angle1 = angleForTab(at: item1.index)
            let angle2 = angleForTab(at: item2.index)
            // Items with higher y (more toward bottom) should render first (lower z)
            return sin(angle1.radians) > sin(angle2.radians)
        }
    }

    /// Update the cache when rotation or tabs change significantly
    private func updateCacheIfNeeded() {
        let rotationChanged = abs(wheelState.rotationAngle - lastRotationAngle) > 5.0
        let tabCountChanged = browserState.tabs.count != lastTabCount

        if rotationChanged || tabCountChanged || cachedSortedTabs.isEmpty {
            cachedSortedTabs = sortedTabsByDepth()
            lastRotationAngle = wheelState.rotationAngle
            lastTabCount = browserState.tabs.count
        }
    }

    // MARK: - Angle & Position Calculations

    private func angleForTab(at index: Int) -> Angle {
        let tabCount = browserState.tabs.count
        guard tabCount > 0 else { return .zero }

        let anglePerTab = 360.0 / Double(tabCount)
        // Start at -90 degrees (12 o'clock) and add rotation
        let baseAngle = Double(index) * anglePerTab - 90.0 + wheelState.rotationAngle

        return Angle(degrees: baseAngle)
    }

    private func positionForAngle(_ angle: Angle, radius r: CGFloat) -> CGPoint {
        let x = cos(angle.radians) * r
        let y = sin(angle.radians) * r
        return CGPoint(x: x, y: y)
    }

    /// Calculate scale based on vertical position
    /// Top (-90°, sin = -1) → scale 1.3 (largest)
    /// Bottom (90°, sin = 1) → scale 0.35 (smallest)
    private func scaleForAngle(_ angle: Angle) -> CGFloat {
        let sinValue = sin(angle.radians) // -1 at top, +1 at bottom
        // Map from [-1, 1] to [1.3, 0.35]
        let scale = 1.3 - (sinValue + 1.0) * 0.475
        return scale
    }

    /// Adjust radius based on scale to create uniform visual spacing
    /// Larger items pushed outward, smaller items pulled inward
    private func radiusForScale(_ scale: CGFloat) -> CGFloat {
        // Normalize scale to 0-1 range (0.35 to 1.3 → 0 to 1)
        let normalizedScale = (scale - 0.35) / 0.95
        // Larger items get pushed out more, smaller items stay closer
        let radiusMultiplier = 0.75 + normalizedScale * 0.35
        return radius * radiusMultiplier
    }

    // MARK: - Actions

    private func selectTab(_ tab: Tab) {
        onSelectTab(tab.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onDismiss()
        }
    }
}
