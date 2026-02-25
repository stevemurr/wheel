import SwiftUI

/// A view modifier that scales a view on hover with spring animation
struct HoverScaleModifier: ViewModifier {
    let scale: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    /// Applies a hover scale effect with spring animation
    /// - Parameter scale: The scale factor when hovered (default: 1.05)
    func hoverScale(_ scale: CGFloat = 1.05) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }
}
