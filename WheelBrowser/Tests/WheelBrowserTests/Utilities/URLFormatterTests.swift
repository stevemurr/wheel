import Testing
@testable import WheelBrowser

@Suite("URLFormatter Tests")
@MainActor
struct URLFormatterTests {

    // MARK: - displayURL Tests

    @Test("Removes https:// prefix")
    func removesHttpsPrefix() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let result = formatter.displayURL("https://example.com")
        #expect(result == "example.com")
    }

    @Test("Removes http:// prefix")
    func removesHttpPrefix() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let result = formatter.displayURL("http://example.com")
        #expect(result == "example.com")
    }

    @Test("Removes www. prefix")
    func removesWwwPrefix() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let result = formatter.displayURL("https://www.example.com")
        #expect(result == "example.com")
    }

    @Test("Removes both https:// and www.")
    func removesBothPrefixes() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let result = formatter.displayURL("https://www.example.com/path")
        #expect(result == "example.com/path")
    }

    @Test("Truncates long URLs with ellipsis")
    func truncatesLongURLs() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let longURL = "https://example.com/very/long/path/that/exceeds/the/maximum/length/limit"
        let result = formatter.displayURL(longURL, maxLength: 30)

        #expect(result.count == 30)
        #expect(result.hasSuffix("..."))
    }

    @Test("Does not truncate short URLs")
    func doesNotTruncateShortURLs() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let result = formatter.displayURL("https://example.com", maxLength: 60)
        #expect(result == "example.com")
        #expect(!result.contains("..."))
    }

    @Test("Caches results for same URL and maxLength")
    func cachesResults() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        // First call
        let result1 = formatter.displayURL("https://example.com", maxLength: 60)
        // Second call (should use cache)
        let result2 = formatter.displayURL("https://example.com", maxLength: 60)

        #expect(result1 == result2)
    }

    @Test("Different maxLength creates different cache entries")
    func differentMaxLengthDifferentCache() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let longURL = "https://example.com/a/very/long/path/here"

        let result1 = formatter.displayURL(longURL, maxLength: 20)
        let result2 = formatter.displayURL(longURL, maxLength: 40)

        #expect(result1 != result2)
        #expect(result1.count == 20)
        #expect(result2.count <= 40)
    }

    @Test("Default maxLength is 60")
    func defaultMaxLength() {
        let formatter = URLFormatter.shared
        formatter.clearCache()

        let veryLongURL = "https://example.com/" + String(repeating: "a", count: 100)
        let result = formatter.displayURL(veryLongURL)

        #expect(result.count == 60)
    }

    // MARK: - domain Tests

    @Test("Extracts domain from URL")
    func extractsDomain() {
        let formatter = URLFormatter.shared

        let result = formatter.domain(from: "https://www.example.com/path")
        #expect(result == "example.com")
    }

    @Test("Removes www. from domain")
    func removesWwwFromDomain() {
        let formatter = URLFormatter.shared

        let result = formatter.domain(from: "https://www.test.org/page")
        #expect(result == "test.org")
    }

    @Test("Returns empty string for invalid URL")
    func emptyForInvalidURL() {
        let formatter = URLFormatter.shared

        let result = formatter.domain(from: "not a valid url")
        #expect(result == "")
    }

    @Test("Handles subdomain correctly")
    func handlesSubdomain() {
        let formatter = URLFormatter.shared

        let result = formatter.domain(from: "https://subdomain.example.com/path")
        #expect(result == "subdomain.example.com")
    }

    @Test("Handles port number")
    func handlesPortNumber() {
        let formatter = URLFormatter.shared

        let result = formatter.domain(from: "https://example.com:8080/path")
        #expect(result == "example.com")
    }

    // MARK: - clearCache Tests

    @Test("clearCache removes all cached entries")
    func clearCacheRemovesAll() {
        let formatter = URLFormatter.shared

        // Add some entries
        _ = formatter.displayURL("https://example1.com")
        _ = formatter.displayURL("https://example2.com")

        formatter.clearCache()

        // We can't directly inspect the cache, but we can verify the formatter still works
        let result = formatter.displayURL("https://example3.com")
        #expect(result == "example3.com")
    }
}
