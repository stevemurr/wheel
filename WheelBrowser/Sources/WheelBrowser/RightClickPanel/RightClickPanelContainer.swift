import SwiftUI
import AppKit

struct RightClickPanelContainer: View {
    @ObservedObject var state: RightClickPanelState
    @ObservedObject var browserState: BrowserState
    let containerSize: CGSize

    // Estimated panel dimensions for clamping (compact layout)
    private let edgePadding: CGFloat = 12

    var body: some View {
        ZStack {
            // The panel itself
            if state.isVisible {
                RightClickPanel(browserState: browserState, onDismiss: state.hide)
                    .position(adjustedPosition)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .onExitCommand {
                        state.hide()
                    }
            }
        }
        // Use a mouse-down monitor for click-outside dismissal instead of blocking overlay
        .background(
            ClickOutsideDetector(
                isEnabled: state.isVisible,
                panelCenter: adjustedPosition,
                panelSize: estimatedPanelSize,
                onClickOutside: { state.hide() }
            )
        )
    }

    // Estimated panel size for bounds checking (larger preview cards)
    private var estimatedPanelSize: CGSize {
        let tabCount = browserState.tabs.count + 1
        let columns = min(tabCount, 4)
        let rows = (tabCount + 3) / 4

        // Card dimensions: 160w x 124h (100 thumbnail + 24 title)
        let cardWidth: CGFloat = 160
        let cardHeight: CGFloat = 124
        let spacing: CGFloat = 12
        let padding: CGFloat = 24 // 12 on each side

        let width = CGFloat(columns) * cardWidth + CGFloat(max(0, columns - 1)) * spacing + padding
        // Navigation bar (~30) + dividers (~18) + actions row (~30) + tab grid
        let height = 30.0 + 18.0 + 30.0 + CGFloat(rows) * cardHeight + CGFloat(max(0, rows - 1)) * spacing + padding

        return CGSize(width: width, height: height)
    }

    // Clamp position to keep panel within bounds
    private var adjustedPosition: CGPoint {
        let size = estimatedPanelSize
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

            // Check if click is outside the panel bounds
            let panelRect = CGRect(
                x: self.panelCenter.x - self.panelSize.width / 2,
                y: self.panelCenter.y - self.panelSize.height / 2,
                width: self.panelSize.width,
                height: self.panelSize.height
            )

            if !panelRect.contains(swiftUIPoint) {
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
