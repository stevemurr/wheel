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

    /// Sections are computed once on `show()` and cached — not recomputed in body.
    private(set) var sections: [ContextMenuSection] = []

    /// Measured by the overlay via GeometryReader preference. Used for edge clamping.
    @ObservationIgnored var measuredCardSize: CGSize = CGSize(width: 240, height: 100)

    /// The web view that will execute actions.
    weak var sourceWebView: BrowserWebView?

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
        // Build sections once and cache
        self.sections = ContextMenuBuilder.buildSections(
            for: hitTest,
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
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
}
