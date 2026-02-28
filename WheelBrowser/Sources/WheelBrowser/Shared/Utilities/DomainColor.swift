import SwiftUI

/// Centralized utility for domain-based color generation
/// Provides consistent colors for domain representations across the app
public enum DomainColor {
    /// The standard color palette for domain representation
    public static let palette: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
    ]

    /// Returns a consistent color for a given domain string
    /// - Parameter domain: The domain string (e.g., "github.com")
    /// - Returns: A color from the palette based on the domain hash
    public static func color(for domain: String) -> Color {
        let hash = domain.utf8.reduce(0) { $0 &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }

    /// Returns a consistent color for a given URL string
    /// - Parameter urlString: The URL string
    /// - Returns: A color based on the host/domain, or a default if no host
    public static func colorForURL(_ urlString: String) -> Color {
        let domain = urlString.urlCleanDomain
        guard !domain.isEmpty else { return .secondary }
        return color(for: domain)
    }
}
