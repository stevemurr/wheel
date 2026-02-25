import SwiftUI

/// A reusable view modifier that provides hover state management with optional callback.
/// Reduces duplicate hover state boilerplate across the codebase.
struct HoverStateModifier: ViewModifier {
    @State private var isHovered = false
    let onHoverChange: ((Bool) -> Void)?

    init(onHoverChange: ((Bool) -> Void)? = nil) {
        self.onHoverChange = onHoverChange
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                onHoverChange?(hovering)
            }
    }
}

/// View extension for easy access to hover state
extension View {
    /// Adds hover state tracking with an optional callback
    func hoverState(onChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverStateModifier(onHoverChange: onChange))
    }
}
