import SwiftUI
import AppKit

/// Captures scroll-wheel events and converts them into zoom-toward-cursor for the Constellation canvas.
struct ConstellationScrollZoomView: NSViewRepresentable {
    @ObservedObject var state: ConstellationState
    let onZoomChanged: () -> Void

    func makeNSView(context: Context) -> ConstellationScrollZoomNSView {
        let view = ConstellationScrollZoomNSView()
        view.state = state
        view.onZoomChanged = onZoomChanged
        return view
    }

    func updateNSView(_ nsView: ConstellationScrollZoomNSView, context: Context) {
        nsView.state = state
        nsView.onZoomChanged = onZoomChanged
        if !state.isVisible {
            nsView.removeMonitor()
        }
    }
}

class ConstellationScrollZoomNSView: NSView {
    var state: ConstellationState?
    var onZoomChanged: (() -> Void)?

    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()

        guard window != nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let state = self.state,
                  state.isVisible,
                  event.window == self.window else {
                return event
            }

            // Verify cursor is within this view's bounds
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else {
                return event
            }

            // Compute zoom factor from scroll delta
            let isPrecise = event.hasPreciseScrollingDeltas
            let delta = isPrecise ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.05
            guard abs(delta) > 0.001 else { return event }
            let factor = 1.0 + delta

            // Reuse locationInView from bounds check, flip Y for SwiftUI top-left origin
            let cursorInCanvas = CGPoint(x: locationInView.x, y: self.bounds.height - locationInView.y)

            let canvasSize = state.canvasSize
            let onZoom = self.onZoomChanged

            MainActor.assumeIsolated {
                state.applyScrollZoom(
                    factor: factor,
                    cursorInCanvas: cursorInCanvas,
                    canvasSize: canvasSize
                )
                onZoom?()
            }

            return nil
        }
    }

    func removeMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
