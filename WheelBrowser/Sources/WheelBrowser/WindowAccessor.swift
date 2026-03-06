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
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 5

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

/// The pill-shaped background view behind the traffic light buttons.
/// Uses a rounded vibrancy subview so the material stays clipped to the capsule.
final class TrafficLightPillView: NSView {
    private let effectView = NSVisualEffectView()
    private let highlightLayer = CAGradientLayer()

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
        layer?.masksToBounds = false

        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.blendingMode = .withinWindow
        effectView.material = .titlebar
        effectView.state = .followsWindowActiveState
        effectView.wantsLayer = true
        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        highlightLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        highlightLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        highlightLayer.locations = [0.0, 0.45, 1.0]
        effectView.layer?.addSublayer(highlightLayer)

        updateColors()
    }

    override func layout() {
        super.layout()
        let cornerRadius = bounds.height / 2
        layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        highlightLayer.frame = effectView.bounds.insetBy(dx: 1, dy: 1)
        highlightLayer.cornerRadius = max(0, cornerRadius - 1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        effectView.layer?.backgroundColor = (
            isDarkMode
                ? NSColor.black.withAlphaComponent(0.18)
                : NSColor.white.withAlphaComponent(0.42)
        ).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (
            isDarkMode
                ? NSColor.white.withAlphaComponent(0.14)
                : NSColor.black.withAlphaComponent(0.10)
        ).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(isDarkMode ? 0.22 : 0.12).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        highlightLayer.colors = [
            (
                isDarkMode
                    ? NSColor.white.withAlphaComponent(0.16)
                    : NSColor.white.withAlphaComponent(0.34)
            ).cgColor,
            (
                isDarkMode
                    ? NSColor.white.withAlphaComponent(0.05)
                    : NSColor.white.withAlphaComponent(0.12)
            ).cgColor,
            NSColor.clear.cgColor
        ]
    }
}

class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}
