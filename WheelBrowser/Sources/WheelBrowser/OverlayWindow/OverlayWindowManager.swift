import SwiftUI

/// Represents a single overlay window displaying web content
@MainActor
@Observable
class OverlayWindowItem: Identifiable, @MainActor FloatingWindowItemProtocol {
    let id = UUID()
    var url: URL
    var title: String
    var position: CGPoint
    var size: CGSize
    var isMinimized: Bool = false
    var isMaximized: Bool = false
    var zIndex: Int
    var webViewRevision: UUID = UUID()
    let createdAt: Date = Date()

    // Store pre-maximize state for restore
    var preMaximizePosition: CGPoint?
    var preMaximizeSize: CGSize?

    init(url: URL, title: String, position: CGPoint, size: CGSize, zIndex: Int) {
        self.url = url
        self.title = title
        self.position = position
        self.size = size
        self.zIndex = zIndex
    }
}

/// Manages overlay windows that float over the main browser content
@MainActor
@Observable
class OverlayWindowManager {
    static let shared = OverlayWindowManager()

    var windows: [OverlayWindowItem] = []
    @ObservationIgnored
    private var nextZIndex = 0
    @ObservationIgnored
    private let maxWindows = 5
    /// O(1) index lookup cache for window items by UUID
    @ObservationIgnored
    private var windowIndexCache: [UUID: Int] = [:]

    // Default window dimensions
    private let defaultSize = CGSize(width: 700, height: 750)
    private let cascadeOffset: CGFloat = 30

    /// Container size for calculating centered positions
    @ObservationIgnored
    var containerSize: CGSize = .zero

    private init() {}

    /// Opens a new overlay window with the specified URL
    /// - Parameters:
    ///   - url: The URL to display in the overlay
    ///   - title: Optional title for the window (defaults to URL host)
    ///   - position: Optional position (cascades from previous window if nil)
    ///   - size: Optional size (uses default 700x500 if nil)
    func openOverlay(url: URL, title: String?, at position: CGPoint? = nil, size: CGSize? = nil) {
        // Enforce maximum window limit
        guard windows.count < maxWindows else { return }

        let windowSize = size ?? defaultSize

        // Fixed upper-right position, cascading for subsequent windows
        let margin: CGFloat = 20
        let basePosition: CGPoint
        if containerSize.width > 0 && containerSize.height > 0 {
            basePosition = CGPoint(
                x: containerSize.width - windowSize.width - margin,
                y: margin
            )
        } else {
            basePosition = CGPoint(x: 100, y: 20)
        }

        let cascadeIndex = CGFloat(windows.count)
        let windowPosition = CGPoint(
            x: max(0, basePosition.x - cascadeIndex * cascadeOffset),
            y: basePosition.y + cascadeIndex * cascadeOffset
        )

        let windowTitle = title ?? url.host ?? url.absoluteString

        let window = OverlayWindowItem(
            url: url,
            title: windowTitle,
            position: windowPosition,
            size: windowSize,
            zIndex: nextZIndex
        )
        nextZIndex += 1

        withAnimation(AppAnimation.springStandard) {
            windows.append(window)
        }
        rebuildIndexCache()
    }

    /// Rebuilds the index cache after structural changes to windows array
    private func rebuildIndexCache() {
        windowIndexCache.removeAll(keepingCapacity: true)
        for (index, item) in windows.enumerated() {
            windowIndexCache[item.id] = index
        }
    }

    /// O(1) lookup for window index by UUID
    private func index(for id: UUID) -> Int? {
        windowIndexCache[id]
    }

    /// Closes the overlay window with the specified ID
    func closeOverlay(id: UUID) {
        withAnimation(AppAnimation.mediumOut) {
            windows.removeAll { $0.id == id }
        }
        rebuildIndexCache()
    }

    /// Closes all overlay windows
    func closeAll() {
        withAnimation(AppAnimation.mediumOut) {
            windows.removeAll()
        }
        windowIndexCache.removeAll()
    }

    /// Brings the specified window to the front
    func bringToFront(id: UUID) {
        guard let idx = index(for: id) else { return }
        windows[idx].zIndex = nextZIndex
        nextZIndex += 1
    }

    /// Minimizes or restores the specified window
    func minimizeOverlay(id: UUID) {
        guard let idx = index(for: id) else { return }
        withAnimation(AppAnimation.springSnappy) {
            windows[idx].isMinimized.toggle()
        }
    }

    /// Toggles maximize state for the specified window
    /// - Parameters:
    ///   - id: The window ID to toggle
    ///   - containerSize: The size of the container to maximize within
    func toggleMaximize(id: UUID, containerSize: CGSize) {
        guard let idx = index(for: id) else { return }
        let window = windows[idx]

        withAnimation(AppAnimation.springStandard) {
            if window.isMaximized {
                // Restore to pre-maximize state
                if let prePosition = window.preMaximizePosition,
                   let preSize = window.preMaximizeSize {
                    window.position = prePosition
                    window.size = preSize
                }
                window.isMaximized = false
            } else {
                // Store current state and maximize
                window.preMaximizePosition = window.position
                window.preMaximizeSize = window.size
                window.position = .zero
                window.size = containerSize
                window.isMaximized = true
            }
        }
    }

    /// Updates the position of the specified window
    func updatePosition(id: UUID, position: CGPoint) {
        guard let idx = index(for: id) else { return }
        windows[idx].position = position
        // If moved while maximized, exit maximize mode
        if windows[idx].isMaximized {
            windows[idx].isMaximized = false
        }
    }

    /// Updates the size of the specified window
    func updateSize(id: UUID, size: CGSize) {
        guard let idx = index(for: id) else { return }
        windows[idx].size = size
        // If resized while maximized, exit maximize mode
        if windows[idx].isMaximized {
            windows[idx].isMaximized = false
        }
    }

    func rebuildAllWebViewsForConfigurationChange() {
        for window in windows {
            window.webViewRevision = UUID()
        }
    }
}
