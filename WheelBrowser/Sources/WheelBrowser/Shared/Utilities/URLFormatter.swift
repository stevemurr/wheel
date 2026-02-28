import Foundation

/// Cached URL formatting to avoid repeated string operations
@MainActor
class URLFormatter {
    static let shared = URLFormatter()

    private var cache: [String: String] = [:]
    private let maxCacheSize = 500

    private init() {}

    /// Format a URL for display, with caching
    func displayURL(_ urlString: String, maxLength: Int = 60) -> String {
        let cacheKey = "\(urlString)_\(maxLength)"

        if let cached = cache[cacheKey] {
            return cached
        }

        var result = urlString
        result = result.replacingOccurrences(of: "https://", with: "")
        result = result.replacingOccurrences(of: "http://", with: "")
        result = result.replacingOccurrences(of: "www.", with: "")

        if result.count > maxLength {
            result = String(result.prefix(maxLength - 3)) + "..."
        }

        // Maintain cache size
        if cache.count >= maxCacheSize {
            // Remove oldest entries (simple FIFO via removing first half)
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 2))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }

        cache[cacheKey] = result
        return result
    }

    /// Extract domain from URL string
    func domain(from urlString: String) -> String {
        urlString.urlCleanDomain
    }

    /// Clear the cache
    func clearCache() {
        cache.removeAll()
    }
}
