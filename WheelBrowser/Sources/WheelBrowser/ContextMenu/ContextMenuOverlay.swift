import SwiftUI
import AppKit

/// Container that positions the context menu card, handles click-outside dismissal,
/// scroll dismissal, and keyboard navigation.
struct ContextMenuOverlay: View {
    var state: ContextMenuState
    let containerSize: CGSize

    private let edgePadding: CGFloat = 8

    /// Sections are computed once per show and cached in state.
    var body: some View {
        ZStack(alignment: .topLeading) {
            if state.isVisible {
                ContextMenuCardView(
                    sections: state.sections,
                    highlightedIndex: state.highlightedIndex,
                    onAction: { action in
                        state.execute(action)
                        state.dismiss()
                    },
                    onHoverChange: { itemID in
                        state.setHoveredItem(itemID)
                        if itemID != nil {
                            state.resetHighlight()
                        }
                    }
                )
                .fixedSize()
                .background(GeometryReader { geo in
                    Color.clear.preference(key: CardSizeKey.self, value: geo.size)
                })
                .onPreferenceChange(CardSizeKey.self) { size in
                    if size != .zero { state.measuredCardSize = size }
                }
                .offset(x: adjustedOrigin.x, y: adjustedOrigin.y)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ContextMenuClickOutsideDetector(
                isEnabled: state.isVisible,
                cardOrigin: adjustedOrigin,
                cardSize: state.measuredCardSize,
                onDismiss: { state.dismiss() },
                onKeyDown: { handleKeyDown($0) },
                onAlternateReleaseInsideCard: { handleAlternateReleaseInsideCard() }
            )
        )
        .onChange(of: containerSize) {
            if state.isVisible { state.dismiss() }
        }
    }

    // MARK: - Edge clamping

    /// Top-left origin for the card, clamped to container bounds.
    private var adjustedOrigin: CGPoint {
        let cardSize = state.measuredCardSize
        var x = state.position.x
        var y = state.position.y

        // Flip if overflowing right
        if x + cardSize.width + edgePadding > containerSize.width {
            x = state.position.x - cardSize.width
        }
        // Flip if overflowing bottom
        if y + cardSize.height + edgePadding > containerSize.height {
            y = state.position.y - cardSize.height
        }

        // Final clamp
        x = min(max(x, edgePadding), containerSize.width - cardSize.width - edgePadding)
        y = min(max(y, edgePadding), containerSize.height - cardSize.height - edgePadding)

        return CGPoint(x: x, y: y)
    }

    // MARK: - Keyboard handling

    private func handleKeyDown(_ event: NSEvent) {
        let enabledCount = state.sections.flatMap(\.items).filter(\.isEnabled).count

        switch Int(event.keyCode) {
        case 125: // Down arrow
            state.moveHighlightDown(count: enabledCount)
        case 126: // Up arrow
            state.moveHighlightUp(count: enabledCount)
        case 36: // Return/Enter
            if let index = state.highlightedIndex {
                let enabledItems = state.sections.flatMap(\.items).filter(\.isEnabled)
                if index < enabledItems.count {
                    state.execute(enabledItems[index].action)
                    state.dismiss()
                }
            }
        case 53: // Escape
            state.dismiss()
        default:
            break
        }
    }

    private func handleAlternateReleaseInsideCard() {
        guard let action = state.hoveredAction() else {
            return
        }
        state.execute(action)
        state.dismiss()
    }
}

// MARK: - Preference key for measuring card size

private struct CardSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Click Outside + Keyboard Detector

private struct ContextMenuClickOutsideDetector: NSViewRepresentable {
    let isEnabled: Bool
    let cardOrigin: CGPoint
    let cardSize: CGSize
    let onDismiss: () -> Void
    let onKeyDown: (NSEvent) -> Void
    let onAlternateReleaseInsideCard: () -> Void

    func makeNSView(context: Context) -> ContextMenuDetectorNSView {
        let view = ContextMenuDetectorNSView()
        view.onDismiss = onDismiss
        view.onKeyDown = onKeyDown
        view.onAlternateReleaseInsideCard = onAlternateReleaseInsideCard
        view.cardOrigin = cardOrigin
        view.cardSize = cardSize
        view.isMonitoringEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: ContextMenuDetectorNSView, context: Context) {
        nsView.onDismiss = onDismiss
        nsView.onKeyDown = onKeyDown
        nsView.onAlternateReleaseInsideCard = onAlternateReleaseInsideCard
        nsView.cardOrigin = cardOrigin
        nsView.cardSize = cardSize
        nsView.isMonitoringEnabled = isEnabled
    }
}

class ContextMenuDetectorNSView: NSView {
    var onDismiss: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?
    var onAlternateReleaseInsideCard: (() -> Void)?
    /// Card rect in SwiftUI coordinates (top-left origin), used for inside/outside test.
    var cardOrigin: CGPoint = .zero
    var cardSize: CGSize = .zero
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

    /// Check whether a window-coordinate click lands inside the card.
    private func isInsideCard(event: NSEvent) -> Bool {
        guard let window = self.window, event.window == window else { return false }
        // Convert window point → this view's local AppKit coords → SwiftUI coords
        let local = convert(event.locationInWindow, from: nil)
        let swiftUI = CGPoint(x: local.x, y: bounds.height - local.y)
        let cardRect = CGRect(origin: cardOrigin, size: cardSize)
        return cardRect.contains(swiftUI)
    }

    private func updateMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        guard isMonitoringEnabled, window != nil else { return }

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseUp, .scrollWheel, .keyDown
        ]

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }

            switch event.type {
            case .leftMouseDown:
                // Only dismiss if click is outside the card
                if !self.isInsideCard(event: event) {
                    DispatchQueue.main.async { self.onDismiss?() }
                }
            case .rightMouseUp:
                if self.isInsideCard(event: event) {
                    DispatchQueue.main.async { self.onAlternateReleaseInsideCard?() }
                }
                return nil
            case .scrollWheel:
                DispatchQueue.main.async { self.onDismiss?() }
            case .keyDown:
                DispatchQueue.main.async { self.onKeyDown?(event) }
                return nil
            default:
                break
            }

            return event
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

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
