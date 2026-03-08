import SwiftUI

/// Container view that renders all overlay windows from the manager
struct OverlayWindowContainer: View {
    var manager: OverlayWindowManager
    let containerSize: CGSize

    var body: some View {
        ZStack {
            ForEach(sortedWindows) { window in
                OverlayWindow(
                    item: window,
                    containerSize: containerSize,
                    onClose: {
                        manager.closeOverlay(id: window.id)
                    },
                    onBringToFront: {
                        manager.bringToFront(id: window.id)
                    },
                    onOpenInTab: {
                        // Post notification to open URL in a new tab
                        NotificationCenter.default.post(
                            name: .openOverlayInTab,
                            object: window.url
                        )
                        manager.closeOverlay(id: window.id)
                    },
                    onMinimize: {
                        manager.minimizeOverlay(id: window.id)
                    },
                    onToggleMaximize: {
                        manager.toggleMaximize(id: window.id, containerSize: containerSize)
                    },
                    onUpdatePosition: { position in
                        manager.updatePosition(id: window.id, position: position)
                    },
                    onUpdateSize: { size in
                        manager.updateSize(id: window.id, size: size)
                    }
                )
                .modifier(FloatingWindowPositionModifier(item: window, containerSize: containerSize))
                .zIndex(Double(window.zIndex))
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    )
                )
            }
        }
        .onAppear {
            manager.containerSize = containerSize
        }
        .onChange(of: containerSize) { _, newSize in
            manager.containerSize = newSize
        }
    }

    /// Windows sorted by zIndex for proper layering
    private var sortedWindows: [OverlayWindowItem] {
        manager.windows.sorted { $0.zIndex < $1.zIndex }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    /// Posted when an overlay window should be opened as a new tab
    /// The object contains the URL to open
    static let openOverlayInTab = Notification.Name("openOverlayInTab")
}
