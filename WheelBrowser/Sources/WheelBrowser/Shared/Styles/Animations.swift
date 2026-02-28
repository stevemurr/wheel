import SwiftUI

enum AppAnimation {
    // MARK: - EaseInOut tiers
    /// Fast interactions: toggles, hover highlights (0.1s)
    static let quick = Animation.easeInOut(duration: 0.1)
    /// Default UI transitions (0.15s)
    static let standard = Animation.easeInOut(duration: 0.15)
    /// Slightly longer transitions: panel reveals, workspace switches (0.2s)
    static let medium = Animation.easeInOut(duration: 0.2)

    // MARK: - EaseOut tiers
    /// Fast dismiss / fade-out (0.1s)
    static let quickOut = Animation.easeOut(duration: 0.1)
    /// Standard dismiss (0.15s)
    static let standardOut = Animation.easeOut(duration: 0.15)
    /// Medium dismiss: overlay fade-out (0.2s)
    static let mediumOut = Animation.easeOut(duration: 0.2)

    // MARK: - Spring animations
    /// Standard spring for general state changes
    static let springStandard = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// Snappy spring for hover interactions
    static let hoverSpring = Animation.spring(response: 0.2, dampingFraction: 0.7)
    /// Smooth spring for panel transitions
    static let panelSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// Snappy spring for quick drawer / preview transitions
    static let springSnappy = Animation.spring(response: 0.25, dampingFraction: 0.8)
    /// Snappy spring with higher damping for drawer containers
    static let springDrawer = Animation.spring(response: 0.25, dampingFraction: 0.85)
}
