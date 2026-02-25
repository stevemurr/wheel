import SwiftUI

/// Shared constants for window and panel styling
enum WindowConstants {
    // MARK: - Corner Radius
    static let panelCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 8
    static let pillCornerRadius: CGFloat = 6

    // MARK: - Shadow
    static let panelShadowRadius: CGFloat = 12
    static let panelShadowOpacity: Double = 0.25
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowOpacity: Double = 0.2

    // MARK: - Panel Dimensions
    static let maxPanelHeight: CGFloat = 500
    static let maxPanelWidth: CGFloat = 700
    static let drawerHeight: CGFloat = 340

    // MARK: - Spacing
    static let defaultPadding: CGFloat = 16
    static let compactPadding: CGFloat = 8
    static let headerPadding: CGFloat = 14

    // MARK: - Animation
    static let defaultAnimationDuration: Double = 0.2
    static let springResponse: Double = 0.3
    static let springDamping: Double = 0.85

    // MARK: - Standard Spring Animation
    static var standardSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
}
