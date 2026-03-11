import SwiftUI
import WebKit

/// Observable state for the custom context menu overlay.
///
/// Singleton pattern matches `TabWheelState`. The `BrowserWebView` publishes
/// hit-test results here instead of building an `NSMenu`.
@MainActor
@Observable
final class ContextMenuState {
    static let shared = ContextMenuState()

    var isVisible = false
    var position: CGPoint = .zero
    var canGoBack = false
    var canGoForward = false
    var highlightedIndex: Int?
    var hoveredItemID: UUID?

    /// Sections are computed once on `show()` and cached — not recomputed in body.
    private(set) var sections: [ContextMenuSection] = []

    /// Measured by the overlay via GeometryReader preference. Used for edge clamping.
    @ObservationIgnored var measuredCardSize: CGSize = CGSize(width: 240, height: 100)

    /// The web view that will execute fallback actions.
    weak var sourceWebView: BrowserWebView?
    @ObservationIgnored private var fallbackActionHandler: ((ContextMenuAction) -> Void)?

    private init() {}

    /// Show the context menu at the given SwiftUI coordinate.
    func show(
        at point: CGPoint,
        hitTest: ContextMenuHitTest,
        canGoBack: Bool,
        canGoForward: Bool,
        source: BrowserWebView
    ) {
        self.position = point
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.sourceWebView = source
        self.highlightedIndex = nil
        self.hoveredItemID = nil
        // Build sections once and cache
        self.sections = ContextMenuBuilder.buildSections(
            for: hitTest,
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
        self.fallbackActionHandler = { [weak source] action in
            source?.executeContextAction(action)
        }
        withAnimation(AppAnimation.quick) {
            self.isVisible = true
        }
    }

    func show(
        at point: CGPoint,
        sections: [ContextMenuSection],
        fallbackAction: ((ContextMenuAction) -> Void)? = nil
    ) {
        self.position = point
        self.canGoBack = false
        self.canGoForward = false
        self.sourceWebView = nil
        self.highlightedIndex = nil
        self.hoveredItemID = nil
        self.sections = sections
        self.fallbackActionHandler = fallbackAction
        withAnimation(AppAnimation.quick) {
            self.isVisible = true
        }
    }

    /// Dismiss the context menu.
    func dismiss() {
        guard isVisible else { return }
        withAnimation(AppAnimation.quickOut) {
            isVisible = false
        }
        highlightedIndex = nil
        hoveredItemID = nil
        fallbackActionHandler = nil
        sourceWebView = nil
    }

    func executeFallback(_ action: ContextMenuAction) {
        fallbackActionHandler?(action)
    }

    // MARK: - Keyboard navigation

    func moveHighlightDown(count: Int) {
        guard count > 0 else { return }
        if let current = highlightedIndex {
            highlightedIndex = min(current + 1, count - 1)
        } else {
            highlightedIndex = 0
        }
    }

    func moveHighlightUp(count: Int) {
        guard count > 0 else { return }
        if let current = highlightedIndex {
            highlightedIndex = max(current - 1, 0)
        } else {
            highlightedIndex = count - 1
        }
    }

    func resetHighlight() {
        highlightedIndex = nil
    }

    func setHoveredItem(_ itemID: UUID?) {
        hoveredItemID = itemID
    }

    func hoveredAction() -> ContextMenuAction? {
        guard let hoveredItemID else { return nil }
        return sections
            .flatMap(\.items)
            .first { $0.id == hoveredItemID && $0.isEnabled }?
            .action
    }
}
