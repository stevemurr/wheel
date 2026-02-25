import Foundation

/// Validates URLs for agent navigation to prevent access to dangerous resources
public struct NavigationPolicy {
    /// URL schemes that are not allowed for agent navigation
    public static let blockedSchemes: Set<String> = [
        "file",
        "javascript",
        "data",
        "blob",
        "about"
    ]

    /// Hosts that are blocked for security reasons
    public static let blockedHosts: Set<String> = [
        "localhost",
        "127.0.0.1",
        "0.0.0.0",
        "169.254.169.254", // AWS metadata endpoint
        "[::1]",          // IPv6 localhost
        "metadata.google.internal" // GCP metadata
    ]

    /// Validates a URL string for agent navigation
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL
    /// - Throws: AgentError.navigationFailed if the URL is not allowed
    public static func validate(_ urlString: String) throws -> URL {
        // Normalize the URL
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if no scheme present
        if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }

        // Parse the URL
        guard let url = URL(string: normalized) else {
            throw AgentError.navigationFailed("Invalid URL format: \(urlString)")
        }

        // Check scheme
        guard let scheme = url.scheme?.lowercased() else {
            throw AgentError.navigationFailed("URL has no scheme: \(urlString)")
        }

        if blockedSchemes.contains(scheme) {
            throw AgentError.navigationFailed("URL scheme '\(scheme)' is not allowed for agent navigation")
        }

        // Only allow http/https
        guard scheme == "http" || scheme == "https" else {
            throw AgentError.navigationFailed("Only http/https URLs are allowed for agent navigation")
        }

        // Check host
        guard let host = url.host?.lowercased() else {
            throw AgentError.navigationFailed("URL has no host: \(urlString)")
        }

        if blockedHosts.contains(host) {
            throw AgentError.navigationFailed("Navigation to '\(host)' is not allowed")
        }

        // Check for private IP ranges
        if isPrivateIP(host) {
            throw AgentError.navigationFailed("Navigation to private IP addresses is not allowed")
        }

        return url
    }

    /// Check if a host string appears to be a private IP address
    private static func isPrivateIP(_ host: String) -> Bool {
        // Simple check for common private IP patterns
        // 10.x.x.x
        if host.hasPrefix("10.") {
            return true
        }

        // 192.168.x.x
        if host.hasPrefix("192.168.") {
            return true
        }

        // 172.16.x.x through 172.31.x.x
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]) {
                if second >= 16 && second <= 31 {
                    return true
                }
            }
        }

        return false
    }
}
