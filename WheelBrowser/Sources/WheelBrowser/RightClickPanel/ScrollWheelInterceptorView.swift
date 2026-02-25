import SwiftUI
import AppKit

struct ScrollWheelInterceptorView: NSViewRepresentable {
    @ObservedObject var wheelState: TabWheelState
    let tabCount: Int

    func makeNSView(context: Context) -> ScrollWheelInterceptorNSView {
        let view = ScrollWheelInterceptorNSView()
        view.wheelState = wheelState
        view.tabCount = tabCount
        return view
    }

    func updateNSView(_ nsView: ScrollWheelInterceptorNSView, context: Context) {
        nsView.wheelState = wheelState
        nsView.tabCount = tabCount
    }
}

class ScrollWheelInterceptorNSView: NSView {
    var wheelState: TabWheelState?
    var tabCount: Int = 0

    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()

        guard window != nil else { return }

        // Monitor scroll wheel events when the wheel UI is visible
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let state = self.wheelState,
                  state.isVisible else {
                return event
            }

            // Handle the scroll event
            // hasPreciseScrollingDeltas: false = mouse wheel (discrete clicks), true = trackpad (continuous)
            let isPrecise = event.hasPreciseScrollingDeltas
            Task { @MainActor in
                state.handleScroll(deltaY: event.scrollingDeltaY, tabCount: self.tabCount, isPrecise: isPrecise)
            }

            // Consume the event to prevent it from scrolling the web content
            return nil
        }
    }

    private func removeMonitor() {
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
        nil // Transparent to hit testing
    }
}
