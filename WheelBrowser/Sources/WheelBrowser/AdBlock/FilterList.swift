import Foundation

// MARK: - Filter List Model

/// Represents an external filter list subscription
struct FilterList: Codable, Identifiable, Equatable {
    /// Unique identifier for the filter list
    let id: UUID

    /// Display name for the filter list
    var name: String

    /// URL to download the filter list from
    let url: URL

    /// Whether this filter list is enabled
    var isEnabled: Bool

    /// Whether this is a built-in default list
    let isBuiltIn: Bool

    /// Last time the list was successfully updated
    var lastUpdated: Date?

    /// Number of rules parsed from the list
    var ruleCount: Int

    /// SHA256 checksum of the last downloaded content (for change detection)
    var checksum: String?

    /// Last error message if fetch/parse failed
    var lastError: String?

    /// Version string from the filter list header
    var version: String?

    /// Homepage URL from the filter list header
    var homepage: String?

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        lastUpdated: Date? = nil,
        ruleCount: Int = 0,
        checksum: String? = nil,
        lastError: String? = nil,
        version: String? = nil,
        homepage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.lastUpdated = lastUpdated
        self.ruleCount = ruleCount
        self.checksum = checksum
        self.lastError = lastError
        self.version = version
        self.homepage = homepage
    }
}

// MARK: - Filter List Metadata

/// Metadata parsed from filter list header comments
struct FilterListMetadata {
    /// Title from [Adblock Plus X.X] or ! Title: header
    var title: String?

    /// Version string
    var version: String?

    /// Homepage URL
    var homepage: String?

    /// Last modified date
    var lastModified: Date?

    /// Expiration interval in hours
    var expiresHours: Int?

    /// License information
    var license: String?

    /// Parse metadata from the raw filter list content
    static func parse(from content: String) -> FilterListMetadata {
        var metadata = FilterListMetadata()

        let lines = content.components(separatedBy: .newlines)

        for line in lines.prefix(50) { // Only check first 50 lines for headers
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Check for [Adblock Plus X.X] header
            if trimmed.hasPrefix("[Adblock") {
                // Extract version from [Adblock Plus 2.0] format
                if let range = trimmed.range(of: #"\d+\.\d+"#, options: .regularExpression) {
                    metadata.version = String(trimmed[range])
                }
                continue
            }

            // Stop parsing headers when we hit a non-comment line
            guard trimmed.hasPrefix("!") else {
                // Allow blank lines but stop at actual rules
                if !trimmed.isEmpty {
                    break
                }
                continue
            }

            // Parse ! Header: Value format
            let headerLine = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)

            if let colonIndex = headerLine.firstIndex(of: ":") {
                let key = String(headerLine[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(headerLine[headerLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

                switch key {
                case "title":
                    metadata.title = value
                case "version":
                    metadata.version = value
                case "homepage":
                    metadata.homepage = value
                case "license":
                    metadata.license = value
                case "last modified":
                    // Parse date formats like "01 Jan 2024 12:00 UTC"
                    let formatter = DateFormatter()
                    formatter.dateFormat = "dd MMM yyyy HH:mm 'UTC'"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(identifier: "UTC")
                    metadata.lastModified = formatter.date(from: value)
                case "expires":
                    // Parse "7 days" or "1 day" format
                    if let match = value.range(of: #"(\d+)\s*(day|hour)"#, options: .regularExpression) {
                        let matched = String(value[match])
                        let components = matched.components(separatedBy: .whitespaces)
                        if components.count >= 2, let number = Int(components[0]) {
                            if matched.contains("day") {
                                metadata.expiresHours = number * 24
                            } else {
                                metadata.expiresHours = number
                            }
                        }
                    }
                default:
                    break
                }
            }
        }

        return metadata
    }
}

// MARK: - Default Filter Lists

extension FilterList {
    /// Default filter lists that come bundled with the browser
    static var defaultLists: [FilterList] {
        [
            FilterList(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "EasyList",
                url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
                isEnabled: true,
                isBuiltIn: true
            ),
            FilterList(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "EasyPrivacy",
                url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
                isEnabled: false,
                isBuiltIn: true
            ),
            FilterList(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Fanboy's Annoyance List",
                url: URL(string: "https://easylist.to/easylist/fanboy-annoyance.txt")!,
                isEnabled: false,
                isBuiltIn: true
            )
        ]
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when filter lists are updated and rules need to be recompiled
    static let filterListsChanged = Notification.Name("filterListsChanged")
}
