import SwiftUI
import AppKit

struct RightClickInterceptorView: NSViewRepresentable {
    let onRightClick: (CGPoint, CGSize) -> Void

    func makeNSView(context: Context) -> RightClickMonitorView {
        let view = RightClickMonitorView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickMonitorView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

class RightClickMonitorView: NSView {
    var onRightClick: ((CGPoint, CGSize) -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Remove any existing monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Add local event monitor for right-click
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  event.window == window else {
                return event
            }

            // Convert to view coordinates
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            // Check if click is within our bounds
            guard self.bounds.contains(locationInView) else {
                return event
            }

            // Convert from AppKit (bottom-left origin) to SwiftUI (top-left origin)
            let swiftUIPoint = CGPoint(
                x: locationInView.x,
                y: self.bounds.height - locationInView.y
            )

            self.onRightClick?(swiftUIPoint, self.bounds.size)

            // Return nil to consume the event (prevents context menu)
            return nil
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

    // This view should be transparent to hit testing
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
