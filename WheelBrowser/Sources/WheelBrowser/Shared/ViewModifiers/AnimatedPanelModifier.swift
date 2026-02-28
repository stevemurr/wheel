import SwiftUI

/// A view modifier for animated panel visibility with scale and offset transitions
struct AnimatedPanelModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .offset(y: isVisible ? 0 : 10)
            .allowsHitTesting(isVisible)
            .frame(maxHeight: isVisible ? nil : 0)
            .clipped()
            .animation(AppAnimation.panelSpring, value: isVisible)
    }
}

extension View {
    /// Applies animated panel visibility modifiers for smooth show/hide transitions
    func animatedPanel(isVisible: Bool) -> some View {
        modifier(AnimatedPanelModifier(isVisible: isVisible))
    }
}
