import SwiftUI
import AppKit

// Allows the window to be dragged from the top area and handles focus
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = FocusableView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isMovableByWindowBackground = true
                window.titlebarAppearsTransparent = true
                // Extend content into title bar area
                window.styleMask.insert(.fullSizeContentView)
                window.makeKeyAndOrderFront(nil)
                window.acceptsMouseMovedEvents = true

                // Add pill-shaped background behind traffic light buttons
                TrafficLightPillManager.shared.addPill(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Traffic Light Pill Background

/// Manages the pill-shaped background behind the traffic light buttons
final class TrafficLightPillManager {
    static let shared = TrafficLightPillManager()

    private var pillView: TrafficLightPillView?
    private weak var observedWindow: NSWindow?
    private var resizeObserver: NSObjectProtocol?

    private init() {}

    deinit {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // Positioning constants
    private let standardLeftMargin: CGFloat = 18
    private let standardTopOffset: CGFloat = 22
    private let buttonSpacing: CGFloat = 22
    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 4

    func addPill(to window: NSWindow) {
        // Remove any existing pill and observer
        pillView?.removeFromSuperview()
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Get references to the traffic light buttons
        guard let closeButton = window.standardWindowButton(.closeButton),
              let _ = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarView = closeButton.superview else {
            return
        }

        // Create and configure the pill view
        let pill = TrafficLightPillView()
        pill.translatesAutoresizingMaskIntoConstraints = false

        // Insert pill behind the buttons
        titlebarView.addSubview(pill, positioned: .below, relativeTo: closeButton)

        // Set pill size (fixed width based on button layout)
        let pillWidth = buttonSpacing * 2 + zoomButton.frame.width + horizontalPadding * 2
        let pillHeight = closeButton.frame.height + verticalPadding * 2

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor, constant: standardLeftMargin - horizontalPadding),
            pill.widthAnchor.constraint(equalToConstant: pillWidth),
            pill.heightAnchor.constraint(equalToConstant: pillHeight)
        ])

        pillView = pill
        observedWindow = window

        // Position buttons initially
        repositionButtons(in: window)

        // Observe window resize to reposition buttons
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.repositionButtons(in: window)
        }
    }

    private func repositionButtons(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarView = closeButton.superview,
              let pill = pillView else {
            return
        }

        // Reposition traffic light buttons
        let buttonY = titlebarView.bounds.height - standardTopOffset - closeButton.frame.height / 2

        closeButton.setFrameOrigin(NSPoint(x: standardLeftMargin, y: buttonY))
        minimizeButton.setFrameOrigin(NSPoint(x: standardLeftMargin + buttonSpacing, y: buttonY))
        zoomButton.setFrameOrigin(NSPoint(x: standardLeftMargin + buttonSpacing * 2, y: buttonY))

        // Update pill vertical position to match buttons
        pill.frame.origin.y = buttonY - verticalPadding
    }
}

/// The pill-shaped background view behind the traffic light buttons
final class TrafficLightPillView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupAppearance()

    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupAppearance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupAppearance() {
        layer?.cornerRadius = bounds.height / 2
        updateColors()
    }

    override func layout() {
        super.layout()
        // Update corner radius when size changes to maintain pill shape
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
    }
}

class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}
