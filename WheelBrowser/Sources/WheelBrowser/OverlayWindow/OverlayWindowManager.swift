import SwiftUI

/// Represents a single overlay window displaying web content
@MainActor
class OverlayWindowItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var title: String
    @Published var position: CGPoint
    @Published var size: CGSize
    @Published var isMinimized: Bool = false
    @Published var isMaximized: Bool = false
    @Published var zIndex: Int
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
class OverlayWindowManager: ObservableObject {
    static let shared = OverlayWindowManager()

    @Published var windows: [OverlayWindowItem] = []
    private var nextZIndex = 0
    private let maxWindows = 5

    // Default window dimensions
    private let defaultSize = CGSize(width: 700, height: 600)
    private let cascadeOffset: CGFloat = 30

    /// Container size for calculating centered positions
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

        // Calculate position with cascade offset if not specified
        let windowPosition: CGPoint
        if let position = position {
            // Position passed in - offset slightly so window doesn't cover click location
            windowPosition = CGPoint(
                x: max(0, position.x - windowSize.width / 2 + 50),
                y: max(0, position.y - 20)
            )
        } else if let lastWindow = windows.last {
            // Cascade from the last window
            windowPosition = CGPoint(
                x: lastWindow.position.x + cascadeOffset,
                y: lastWindow.position.y + cascadeOffset
            )
        } else if containerSize.width > 0 && containerSize.height > 0 {
            // Center in container with slight offset toward top-right
            windowPosition = CGPoint(
                x: (containerSize.width - windowSize.width) / 2 + 50,
                y: (containerSize.height - windowSize.height) / 2 - 30
            )
        } else {
            // Fallback if container size not yet known
            windowPosition = CGPoint(x: 100, y: 80)
        }

        let windowTitle = title ?? url.host ?? url.absoluteString

        let window = OverlayWindowItem(
            url: url,
            title: windowTitle,
            position: windowPosition,
            size: windowSize,
            zIndex: nextZIndex
        )
        nextZIndex += 1

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            windows.append(window)
        }
    }

    /// Closes the overlay window with the specified ID
    func closeOverlay(id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            windows.removeAll { $0.id == id }
        }
    }

    /// Closes all overlay windows
    func closeAll() {
        withAnimation(.easeOut(duration: 0.2)) {
            windows.removeAll()
        }
    }

    /// Brings the specified window to the front
    func bringToFront(id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].zIndex = nextZIndex
        nextZIndex += 1
    }

    /// Minimizes or restores the specified window
    func minimizeOverlay(id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            windows[index].isMinimized.toggle()
        }
    }

    /// Toggles maximize state for the specified window
    /// - Parameters:
    ///   - id: The window ID to toggle
    ///   - containerSize: The size of the container to maximize within
    func toggleMaximize(id: UUID, containerSize: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows[index]

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].position = position
        // If moved while maximized, exit maximize mode
        if windows[index].isMaximized {
            windows[index].isMaximized = false
        }
    }

    /// Updates the size of the specified window
    func updateSize(id: UUID, size: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].size = size
        // If resized while maximized, exit maximize mode
        if windows[index].isMaximized {
            windows[index].isMaximized = false
        }
    }
}
