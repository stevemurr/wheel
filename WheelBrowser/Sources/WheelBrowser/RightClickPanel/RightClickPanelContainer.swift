import SwiftUI
import AppKit

struct RightClickPanelContainer: View {
    var state: TabWheelState
    var browserState: BrowserState
    let containerSize: CGSize

    private let edgePadding: CGFloat = 20

    var body: some View {
        ZStack {
            // Scroll wheel interceptor (always present to capture scroll events)
            ScrollWheelInterceptorView(
                wheelState: state,
                tabCount: browserState.tabs.count
            )

            // The wheel panel itself
            if state.isVisible {
                TabWheelView(
                    browserState: browserState,
                    wheelState: state,
                    onSelectTab: { tabId in
                        browserState.selectTab(tabId)
                    },
                    onDismiss: {
                        state.hide()
                        state.reset()
                    }
                )
                .position(adjustedPosition)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .onExitCommand {
                    state.hide()
                    state.reset()
                }
            }
        }
        // Use a mouse-down monitor for click-outside dismissal
        .background(
            ClickOutsideDetector(
                isEnabled: state.isVisible,
                panelCenter: adjustedPosition,
                panelSize: estimatedWheelSize,
                onClickOutside: {
                    state.hide()
                    state.reset()
                }
            )
        )
    }

    // Estimated wheel size for bounds checking
    private var estimatedWheelSize: CGSize {
        let count = browserState.tabs.count
        let radius: CGFloat
        let baseItemSize: CGFloat

        if count <= 4 {
            radius = 130
            baseItemSize = 80
        } else if count <= 8 {
            radius = 160
            baseItemSize = 70
        } else {
            radius = min(200, 130 + CGFloat(count - 4) * 10)
            baseItemSize = max(55, 80 - CGFloat(count - 4) * 3)
        }

        let totalSize = radius * 2 + baseItemSize * 1.8 + 60
        return CGSize(width: totalSize, height: totalSize)
    }

    // Clamp position to keep wheel within bounds
    private var adjustedPosition: CGPoint {
        let size = estimatedWheelSize
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let x = min(
            max(state.position.x, halfWidth + edgePadding),
            containerSize.width - halfWidth - edgePadding
        )

        let y = min(
            max(state.position.y, halfHeight + edgePadding),
            containerSize.height - halfHeight - edgePadding
        )

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Click Outside Detector

/// Detects left-clicks outside the panel using an event monitor (non-blocking)
private struct ClickOutsideDetector: NSViewRepresentable {
    let isEnabled: Bool
    let panelCenter: CGPoint
    let panelSize: CGSize
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> ClickOutsideNSView {
        let view = ClickOutsideNSView()
        view.onClickOutside = onClickOutside
        view.isMonitoringEnabled = isEnabled
        view.panelCenter = panelCenter
        view.panelSize = panelSize
        return view
    }

    func updateNSView(_ nsView: ClickOutsideNSView, context: Context) {
        nsView.onClickOutside = onClickOutside
        nsView.isMonitoringEnabled = isEnabled
        nsView.panelCenter = panelCenter
        nsView.panelSize = panelSize
    }
}

private class ClickOutsideNSView: NSView {
    var onClickOutside: (() -> Void)?
    var panelCenter: CGPoint = .zero
    var panelSize: CGSize = .zero
    private var eventMonitor: Any?

    var isMonitoringEnabled: Bool = false {
        didSet {
            if isMonitoringEnabled != oldValue {
                updateMonitor()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    private func updateMonitor() {
        // Remove existing monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Only add monitor when enabled and in a window
        guard isMonitoringEnabled, window != nil else { return }

        // Monitor left mouse down to detect clicks outside the panel
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  event.window == window else {
                return event
            }

            // Convert click to view coordinates
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            // Convert to SwiftUI coordinates (top-left origin)
            let swiftUIPoint = CGPoint(
                x: locationInView.x,
                y: self.bounds.height - locationInView.y
            )

            // Check if click is outside the panel bounds (circular area)
            let dx = swiftUIPoint.x - self.panelCenter.x
            let dy = swiftUIPoint.y - self.panelCenter.y
            let distance = sqrt(dx * dx + dy * dy)
            let radius = min(self.panelSize.width, self.panelSize.height) / 2

            if distance > radius {
                // Click is outside - dismiss
                DispatchQueue.main.async {
                    self.onClickOutside?()
                }
            }

            return event // Always pass event through
        }
    }

    override func removeFromSuperview() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        super.removeFromSuperview()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // Transparent to hit testing
    }
}
