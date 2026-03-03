import Foundation
import CryptoKit

// MARK: - Filter List Fetcher

/// Actor for downloading and processing filter lists.
/// Supports HTTP conditional requests (ETag / Last-Modified) to avoid re-downloading unchanged content.
actor FilterListFetcher {

    /// Shared instance
    static let shared = FilterListFetcher()

    /// URLSession for downloading
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch Methods

    /// Fetch a filter list from URL with optional conditional request headers.
    /// - Parameters:
    ///   - url: URL to fetch from
    ///   - etag: Previous ETag for If-None-Match
    ///   - lastModified: Previous Last-Modified for If-Modified-Since
    /// - Returns: Content string and response headers, or nil if not modified (304)
    func fetch(
        from url: URL,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> (content: String, etag: String?, lastModified: String?)? {
        var request = URLRequest(url: url)

        // Add conditional headers
        if let etag = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FilterListError.invalidResponse
        }

        // 304 Not Modified — content hasn't changed
        if httpResponse.statusCode == 304 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw FilterListError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw FilterListError.invalidEncoding
        }

        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        return (content, responseEtag, responseLastModified)
    }

    /// Result of fetching and processing a filter list
    struct FetchResult {
        let filterList: FilterList
        let rules: [[String: Any]]
        let cosmeticFilters: ProcessedCosmeticFilters
        let scriptletRules: [ScriptletRule]
    }

    /// Fetch and process a filter list
    /// - Parameters:
    ///   - filterList: The filter list to update
    ///   - forceUpdate: Whether to update even if checksum hasn't changed
    /// - Returns: Updated filter list, converted rules, cosmetic filters, and scriptlet rules, or nil if unchanged
    func fetchAndProcess(
        _ filterList: FilterList,
        forceUpdate: Bool = false
    ) async throws -> FetchResult? {

        // Use conditional request headers unless forcing
        let etag = forceUpdate ? nil : filterList.etag
        let lastModified = forceUpdate ? nil : filterList.lastModifiedHeader

        guard let fetchResult = try await fetch(
            from: filterList.url,
            etag: etag,
            lastModified: lastModified
        ) else {
            // 304 Not Modified
            return nil
        }

        let content = fetchResult.content

        // Calculate checksum
        let checksum = calculateChecksum(content)

        // Skip if unchanged (unless forced)
        if !forceUpdate && checksum == filterList.checksum {
            return nil
        }

        // Parse metadata
        let metadata = FilterListMetadata.parse(from: content)

        // Parse rules
        let parser = ABPParser()
        let parsedRules = await parser.parse(content)

        // Convert to WebKit format
        let converter = WebKitRuleConverter()
        let (webkitRules, stats) = converter.convertWithStats(parsedRules)

        // Extract cosmetic filters for JS-based hiding
        let cosmeticProcessor = CosmeticFilterListProcessor()
        let cosmeticFilters = await cosmeticProcessor.process(parsedRules)

        // Extract scriptlet injection rules
        let scriptletRules = parsedRules.compactMap { rule -> ScriptletRule? in
            if case .scriptletInject(let scriptlet) = rule {
                return scriptlet
            }
            return nil
        }

        // Update filter list
        var updatedList = filterList
        updatedList.lastUpdated = Date()
        updatedList.checksum = checksum
        updatedList.ruleCount = stats.totalConverted
        updatedList.lastError = nil
        updatedList.version = metadata.version
        updatedList.homepage = metadata.homepage
        updatedList.etag = fetchResult.etag
        updatedList.lastModifiedHeader = fetchResult.lastModified

        if stats.truncated {
            Log.AdBlock.warning("\(filterList.name) truncated to \(WebKitRuleConverter.maxRulesPerList) rules")
        }

        return FetchResult(
            filterList: updatedList,
            rules: webkitRules,
            cosmeticFilters: cosmeticFilters,
            scriptletRules: scriptletRules
        )
    }

    // MARK: - Checksum

    /// Calculate SHA256 checksum of content
    func calculateChecksum(_ content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum FilterListError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidEncoding
    case parseError(String)
    case storageError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode):
            return "HTTP error \(statusCode)"
        case .invalidEncoding:
            return "Invalid text encoding"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .storageError(let message):
            return "Storage error: \(message)"
        }
    }
}
