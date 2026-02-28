import SwiftUI
import AppKit

struct RightClickInterceptorView: NSViewRepresentable {
    let onMiddleClick: (CGPoint, CGSize) -> Void

    func makeNSView(context: Context) -> RightClickMonitorView {
        let view = RightClickMonitorView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: RightClickMonitorView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }
}

class RightClickMonitorView: NSView {
    var onMiddleClick: ((CGPoint, CGSize) -> Void)?

    // Consolidated event monitors
    private var monitors: [Any] = []

    // Shared state for distinguishing click vs drag
    private var gestureDownLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var isDragging = false
    private var isOptionClickActive = false
    private let dragThreshold: CGFloat = 3.0

    /// Add a local event monitor and track it for later removal
    @discardableResult
    private func addMonitor(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        if let monitor = monitor {
            monitors.append(monitor)
        }
        return monitor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeAllMonitors()

        guard let window = window else { return }

        // MARK: - Middle-click monitors

        // Monitor middle mouse down
        addMonitor(matching: .otherMouseDown) { [weak self] event in
            guard event.buttonNumber == 2 else { return event }
            self?.gestureDownLocation = NSEvent.mouseLocation
            self?.initialWindowOrigin = window.frame.origin
            self?.isDragging = false
            return nil
        }

        // Monitor middle mouse dragged - manually move window
        addMonitor(matching: .otherMouseDragged) { [weak self] event in
            guard event.buttonNumber == 2,
                  let self = self,
                  let startMouseLocation = self.gestureDownLocation,
                  let startWindowOrigin = self.initialWindowOrigin else {
                return event
            }

            let currentMouseLocation = NSEvent.mouseLocation
            let dx = currentMouseLocation.x - startMouseLocation.x
            let dy = currentMouseLocation.y - startMouseLocation.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance >= self.dragThreshold {
                self.isDragging = true
                let newOrigin = NSPoint(
                    x: startWindowOrigin.x + dx,
                    y: startWindowOrigin.y + dy
                )
                window.setFrameOrigin(newOrigin)
            }

            return nil
        }

        // Monitor middle mouse up
        addMonitor(matching: .otherMouseUp) { [weak self] event in
            guard event.buttonNumber == 2, let self = self else { return event }

            defer {
                self.gestureDownLocation = nil
                self.initialWindowOrigin = nil
                self.isDragging = false
            }

            if !self.isDragging {
                self.triggerContextMenu(from: event)
            }

            return nil
        }

        // MARK: - Option+click monitors (trackpad support)

        // Monitor Option+left click down
        addMonitor(matching: .leftMouseDown) { [weak self] event in
            guard event.modifierFlags.contains(.option) else { return event }

            self?.gestureDownLocation = NSEvent.mouseLocation
            self?.initialWindowOrigin = window.frame.origin
            self?.isDragging = false
            self?.isOptionClickActive = true
            return nil
        }

        // Monitor Option+left click drag - move window
        addMonitor(matching: .leftMouseDragged) { [weak self] event in
            guard let self = self,
                  self.isOptionClickActive,
                  let startMouseLocation = self.gestureDownLocation,
                  let startWindowOrigin = self.initialWindowOrigin else {
                return event
            }

            let currentMouseLocation = NSEvent.mouseLocation
            let dx = currentMouseLocation.x - startMouseLocation.x
            let dy = currentMouseLocation.y - startMouseLocation.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance >= self.dragThreshold {
                self.isDragging = true
                let newOrigin = NSPoint(
                    x: startWindowOrigin.x + dx,
                    y: startWindowOrigin.y + dy
                )
                window.setFrameOrigin(newOrigin)
            }

            return nil
        }

        // Monitor Option+left click up
        addMonitor(matching: .leftMouseUp) { [weak self] event in
            guard let self = self, self.isOptionClickActive else { return event }

            defer {
                self.gestureDownLocation = nil
                self.initialWindowOrigin = nil
                self.isDragging = false
                self.isOptionClickActive = false
            }

            if !self.isDragging {
                self.triggerContextMenu(from: event)
            }

            return nil
        }
    }

    private func triggerContextMenu(from event: NSEvent) {
        let locationInWindow = event.locationInWindow
        let locationInView = self.convert(locationInWindow, from: nil)

        if self.bounds.contains(locationInView) {
            let swiftUIPoint = CGPoint(
                x: locationInView.x,
                y: self.bounds.height - locationInView.y
            )
            self.onMiddleClick?(swiftUIPoint, self.bounds.size)
        }
    }

    private func removeAllMonitors() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    override func removeFromSuperview() {
        removeAllMonitors()
        super.removeFromSuperview()
    }

    deinit {
        removeAllMonitors()
    }

    // This view should be transparent to hit testing
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
