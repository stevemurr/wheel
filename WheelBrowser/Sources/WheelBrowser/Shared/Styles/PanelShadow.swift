import SwiftUI

/// Unified shadow specifications for panels throughout the app
struct PanelShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Standard shadow for primary panels (OmniPanel, ChatResponsePanel)
    static let standard = PanelShadow(
        color: Color.black.opacity(0.12),
        radius: 12,
        x: 0,
        y: 4
    )

    /// Subtle shadow for secondary elements (dropdowns, chips)
    static let subtle = PanelShadow(
        color: Color.black.opacity(0.08),
        radius: 8,
        x: 0,
        y: 2
    )

    /// Elevated shadow for floating elements (overlays, modals)
    static let elevated = PanelShadow(
        color: Color.black.opacity(0.20),
        radius: 20,
        x: 0,
        y: 8
    )
}

// MARK: - View Extension for convenient shadow application

extension View {
    /// Apply a standard panel shadow
    func panelShadow(_ style: PanelShadow = .standard) -> some View {
        self.shadow(
            color: style.color,
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
}
