import SwiftUI

/// Consolidated card styling used across panels and widgets
struct CardStyleModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 12
    var shadowOpacity: Double = 0.25
    var borderOpacity: Double = 0.5
    var borderColor: Color = .blue

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor.opacity(borderOpacity), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func cardStyle(
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 12,
        shadowOpacity: Double = 0.25,
        borderOpacity: Double = 0.5,
        borderColor: Color = .blue
    ) -> some View {
        modifier(CardStyleModifier(
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity,
            borderOpacity: borderOpacity,
            borderColor: borderColor
        ))
    }
}
