import Foundation
import CryptoKit

// MARK: - Filter List Fetcher

/// Actor for downloading and processing filter lists
actor FilterListFetcher {

    /// Shared instance
    static let shared = FilterListFetcher()

    /// URLSession for downloading
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch Methods

    /// Fetch a filter list from URL
    /// - Parameter url: URL to fetch from
    /// - Returns: The raw content string
    func fetch(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FilterListError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw FilterListError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw FilterListError.invalidEncoding
        }

        return content
    }

    /// Fetch and process a filter list
    /// - Parameters:
    ///   - filterList: The filter list to update
    ///   - forceUpdate: Whether to update even if checksum hasn't changed
    /// - Returns: Updated filter list and converted rules, or nil if unchanged
    func fetchAndProcess(
        _ filterList: FilterList,
        forceUpdate: Bool = false
    ) async throws -> (filterList: FilterList, rules: [[String: Any]])? {

        // Fetch content
        let content = try await fetch(from: filterList.url)

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

        // Update filter list
        var updatedList = filterList
        updatedList.lastUpdated = Date()
        updatedList.checksum = checksum
        updatedList.ruleCount = stats.totalConverted
        updatedList.lastError = nil
        updatedList.version = metadata.version
        updatedList.homepage = metadata.homepage

        if stats.truncated {
            print("FilterListFetcher: \(filterList.name) truncated to \(WebKitRuleConverter.maxRulesPerList) rules")
        }

        return (updatedList, webkitRules)
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
