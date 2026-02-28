import Foundation

extension URL {
    /// Returns the domain without common prefixes like "www."
    /// - Returns: A clean domain string (e.g., "example.com" from "https://www.example.com/path")
    var cleanDomain: String {
        guard let host = self.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// Returns the first character of the clean domain, uppercased
    /// Useful for favicon placeholder initials
    var domainInitial: String {
        String(cleanDomain.prefix(1)).uppercased()
    }
}

extension String {
    /// Parses the string as a URL and returns the clean domain
    /// - Returns: A clean domain string, or empty string if the URL is invalid
    var urlCleanDomain: String {
        guard let url = URL(string: self) else { return "" }
        return url.cleanDomain
    }

    /// Removes the "www." prefix from a host string if present
    var removingWWWPrefix: String {
        replacingOccurrences(of: "www.", with: "")
    }
}
