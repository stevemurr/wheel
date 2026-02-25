import SwiftUI
import AppKit

struct LinkPreviewDismissDetector: NSViewRepresentable {
    @ObservedObject var state = LinkPreviewState.shared
    let panelFrame: CGRect

    func makeNSView(context: Context) -> LinkPreviewTrackingView {
        let view = LinkPreviewTrackingView()
        view.onMouseMoved = { [weak state] location in
            guard let state = state, state.isVisible else { return }

            // Check if mouse is outside both the link area and the panel
            // For now, we dismiss when mouse moves significantly away from the panel
            let expandedPanelFrame = panelFrame.insetBy(dx: -20, dy: -20)
            if !expandedPanelFrame.contains(location) {
                Task { @MainActor in
                    state.dismiss()
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: LinkPreviewTrackingView, context: Context) {
        // Update panel frame if needed
    }
}

class LinkPreviewTrackingView: NSView {
    var onMouseMoved: ((CGPoint) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var eventMonitor: Any?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Add global mouse event monitor
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                if let location = self?.window?.mouseLocationOutsideOfEventStream {
                    self?.onMouseMoved?(location)
                }
                return event
            }
        } else {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
