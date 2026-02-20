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

    // Middle-click monitors
    private var middleDownMonitor: Any?
    private var middleUpMonitor: Any?
    private var middleDragMonitor: Any?

    // Option+click monitors (trackpad support)
    private var optionClickDownMonitor: Any?
    private var optionClickUpMonitor: Any?
    private var optionClickDragMonitor: Any?

    // Shared state for distinguishing click vs drag
    private var gestureDownLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var isDragging = false
    private var isOptionClickActive = false
    private let dragThreshold: CGFloat = 3.0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeAllMonitors()

        guard let window = window else { return }

        // MARK: - Middle-click monitors

        // Monitor middle mouse down
        middleDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard event.buttonNumber == 2 else { return event }
            self?.gestureDownLocation = NSEvent.mouseLocation
            self?.initialWindowOrigin = window.frame.origin
            self?.isDragging = false
            return nil
        }

        // Monitor middle mouse dragged - manually move window
        middleDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { [weak self] event in
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
                // Manually move the window
                let newOrigin = NSPoint(
                    x: startWindowOrigin.x + dx,
                    y: startWindowOrigin.y + dy
                )
                window.setFrameOrigin(newOrigin)
            }

            return nil
        }

        // Monitor middle mouse up
        middleUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard event.buttonNumber == 2, let self = self else { return event }

            defer {
                self.gestureDownLocation = nil
                self.initialWindowOrigin = nil
                self.isDragging = false
            }

            // If we didn't drag, it's a click - show context menu
            if !self.isDragging {
                self.triggerContextMenu(from: event)
            }

            return nil
        }

        // MARK: - Option+click monitors (trackpad support)

        // Monitor Option+left click down
        optionClickDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // Check if Option key is held
            guard event.modifierFlags.contains(.option) else { return event }

            self?.gestureDownLocation = NSEvent.mouseLocation
            self?.initialWindowOrigin = window.frame.origin
            self?.isDragging = false
            self?.isOptionClickActive = true
            return nil  // Consume the event
        }

        // Monitor Option+left click drag - move window
        optionClickDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
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
                // Manually move the window
                let newOrigin = NSPoint(
                    x: startWindowOrigin.x + dx,
                    y: startWindowOrigin.y + dy
                )
                window.setFrameOrigin(newOrigin)
            }

            return nil  // Consume the event
        }

        // Monitor Option+left click up
        optionClickUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self, self.isOptionClickActive else { return event }

            defer {
                self.gestureDownLocation = nil
                self.initialWindowOrigin = nil
                self.isDragging = false
                self.isOptionClickActive = false
            }

            // If we didn't drag, it's a click - show context menu
            if !self.isDragging {
                self.triggerContextMenu(from: event)
            }

            return nil  // Consume the event
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
        // Remove middle-click monitors
        if let monitor = middleDownMonitor {
            NSEvent.removeMonitor(monitor)
            middleDownMonitor = nil
        }
        if let monitor = middleUpMonitor {
            NSEvent.removeMonitor(monitor)
            middleUpMonitor = nil
        }
        if let monitor = middleDragMonitor {
            NSEvent.removeMonitor(monitor)
            middleDragMonitor = nil
        }
        // Remove Option+click monitors
        if let monitor = optionClickDownMonitor {
            NSEvent.removeMonitor(monitor)
            optionClickDownMonitor = nil
        }
        if let monitor = optionClickUpMonitor {
            NSEvent.removeMonitor(monitor)
            optionClickUpMonitor = nil
        }
        if let monitor = optionClickDragMonitor {
            NSEvent.removeMonitor(monitor)
            optionClickDragMonitor = nil
        }
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
