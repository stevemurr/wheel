import SwiftUI

/// Utility for generating consistent gradients and initials based on domain names
struct DomainGradient {
    /// Generate a consistent gradient based on the domain host
    /// - Parameter host: The URL host (e.g., "www.example.com")
    /// - Returns: A linear gradient from top-leading to bottom-trailing
    static func gradient(for host: String?) -> LinearGradient {
        let colors: [Color]
        if let host = host {
            let cleanHost = host.replacingOccurrences(of: "www.", with: "")
            let hash = abs(cleanHost.hashValue)
            let hue1 = Double(hash % 360) / 360.0
            let hue2 = Double((hash / 360) % 360) / 360.0

            colors = [
                Color(hue: hue1, saturation: 0.5, brightness: 0.6),
                Color(hue: hue2, saturation: 0.5, brightness: 0.4)
            ]
        } else {
            colors = [
                Color.gray.opacity(0.5),
                Color.gray.opacity(0.3)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Generate a consistent gradient for placeholders with lower saturation
    /// - Parameter host: The URL host (e.g., "www.example.com")
    /// - Returns: A linear gradient suitable for placeholder backgrounds
    static func placeholderGradient(for host: String?) -> LinearGradient {
        let colors: [Color]
        if let host = host {
            let cleanHost = host.replacingOccurrences(of: "www.", with: "")
            let hash = abs(cleanHost.hashValue)
            let hue1 = Double(hash % 360) / 360.0
            let hue2 = Double((hash / 360) % 360) / 360.0

            colors = [
                Color(hue: hue1, saturation: 0.3, brightness: 0.4),
                Color(hue: hue2, saturation: 0.3, brightness: 0.3)
            ]
        } else {
            colors = [
                Color(nsColor: .systemGray).opacity(0.3),
                Color(nsColor: .systemGray).opacity(0.2)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Get the initial character for a domain
    /// - Parameter host: The URL host (e.g., "www.example.com")
    /// - Returns: The uppercase first character of the domain (without www.)
    static func initial(for host: String?) -> String {
        if let host = host {
            let cleanHost = host.replacingOccurrences(of: "www.", with: "")
            return String(cleanHost.prefix(1)).uppercased()
        }
        return "N"
    }
}
