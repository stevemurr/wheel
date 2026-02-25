import SwiftUI

/// View modifier that applies consistent panel styling across the app
/// Includes background, border, shadow, and clip shape
struct PanelStyleModifier: ViewModifier {
    let cornerRadius: CGFloat
    let borderColor: Color
    let borderWidth: CGFloat
    let shadowRadius: CGFloat
    let shadowOpacity: Double

    init(
        cornerRadius: CGFloat = 12,
        borderColor: Color = .blue,
        borderWidth: CGFloat = 1.0,
        shadowRadius: CGFloat = 12,
        shadowOpacity: Double = 0.25
    ) {
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor.opacity(0.5), lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
    }
}

extension View {
    /// Apply standard panel styling with customizable parameters
    /// - Parameters:
    ///   - cornerRadius: Corner radius for the panel (default: 12)
    ///   - borderColor: Border color (default: .blue)
    ///   - borderWidth: Border width (default: 1.0)
    ///   - shadowRadius: Shadow blur radius (default: 12)
    ///   - shadowOpacity: Shadow opacity (default: 0.25)
    /// - Returns: A view with panel styling applied
    func panelStyle(
        cornerRadius: CGFloat = 12,
        borderColor: Color = .blue,
        borderWidth: CGFloat = 1.0,
        shadowRadius: CGFloat = 12,
        shadowOpacity: Double = 0.25
    ) -> some View {
        modifier(PanelStyleModifier(
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity
        ))
    }
}
