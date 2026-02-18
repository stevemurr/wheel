import Foundation

// MARK: - ABP Rule Types

/// Represents a parsed AdBlock Plus filter rule
enum ABPRule {
    case urlBlock(URLBlockRule)
    case urlException(URLBlockRule)
    case cssHide(CSSHideRule)
    case cssException(CSSHideRule)
    case comment(String)
    case unsupported(String)
}

/// URL-based blocking rule
struct URLBlockRule {
    /// The URL pattern to match
    let pattern: String

    /// Resource types to match (empty = all types)
    let resourceTypes: Set<ABPResourceType>

    /// Load type (first-party, third-party, or both)
    let loadType: ABPLoadType

    /// Domains where this rule should apply (empty = all domains)
    let includeDomains: [String]

    /// Domains where this rule should NOT apply
    let excludeDomains: [String]

    /// Whether this is a domain anchor rule (||)
    let isDomainAnchor: Bool

    /// Whether this is an address start anchor (|)
    let isAddressStartAnchor: Bool

    /// Whether this is an address end anchor (|)
    let isAddressEndAnchor: Bool

    /// Case sensitivity
    let matchCase: Bool
}

/// CSS element hiding rule
struct CSSHideRule {
    /// CSS selector to hide
    let selector: String

    /// Domains where this rule applies (empty = all domains)
    let includeDomains: [String]

    /// Domains where this rule should NOT apply
    let excludeDomains: [String]
}

/// Resource types for URL blocking
enum ABPResourceType: String, CaseIterable {
    case script
    case image
    case stylesheet
    case font
    case media
    case xmlhttprequest
    case websocket
    case document
    case subdocument
    case popup
    case other

    /// Convert to WebKit resource type string
    var webkitType: String? {
        switch self {
        case .script: return "script"
        case .image: return "image"
        case .stylesheet: return "style-sheet"
        case .font: return "font"
        case .media: return "media"
        case .xmlhttprequest: return "fetch"
        case .document: return "document"
        case .subdocument: return "document"
        case .popup: return "popup"
        case .other: return "raw"
        case .websocket: return nil // Not directly supported
        }
    }
}

/// Load type for URL blocking
enum ABPLoadType {
    case all
    case firstParty
    case thirdParty
}

// MARK: - ABP Parser

/// Parser for AdBlock Plus filter syntax
actor ABPParser {

    /// Parse a filter list content into rules
    /// - Parameter content: The raw filter list text content
    /// - Returns: Array of parsed rules
    func parse(_ content: String) async -> [ABPRule] {
        let lines = content.components(separatedBy: .newlines)
        var rules: [ABPRule] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Parse the line
            let rule = parseLine(trimmed)
            rules.append(rule)
        }

        return rules
    }

    /// Parse a single filter line
    private func parseLine(_ line: String) -> ABPRule {
        // Comments
        if line.hasPrefix("!") || line.hasPrefix("[Adblock") {
            return .comment(line)
        }

        // CSS exception rules (#@#)
        if let separatorRange = line.range(of: "#@#") {
            return parseCSSException(line, separatorRange: separatorRange)
        }

        // CSS hiding rules (##)
        if let separatorRange = line.range(of: "##") {
            return parseCSSHide(line, separatorRange: separatorRange)
        }

        // CSS hiding with extended syntax (#?#, #$#, etc.) - not supported
        if line.contains("#?#") || line.contains("#$#") || line.contains("#%#") {
            return .unsupported(line)
        }

        // URL exception rules (@@)
        if line.hasPrefix("@@") {
            if let urlRule = parseURLRule(String(line.dropFirst(2))) {
                return .urlException(urlRule)
            }
            return .unsupported(line)
        }

        // URL blocking rules
        if let urlRule = parseURLRule(line) {
            return .urlBlock(urlRule)
        }

        return .unsupported(line)
    }

    // MARK: - URL Rule Parsing

    private func parseURLRule(_ line: String) -> URLBlockRule? {
        var pattern = line
        var resourceTypes: Set<ABPResourceType> = []
        var loadType: ABPLoadType = .all
        var includeDomains: [String] = []
        var excludeDomains: [String] = []
        var matchCase = false
        var isDomainAnchor = false
        var isAddressStartAnchor = false
        var isAddressEndAnchor = false

        // Parse options after $
        if let dollarIndex = pattern.lastIndex(of: "$") {
            let optionsPart = String(pattern[pattern.index(after: dollarIndex)...])
            pattern = String(pattern[..<dollarIndex])

            // Check if this looks like options (contains known option keywords)
            // Skip if it looks like part of a URL (e.g., $1)
            if optionsPart.contains(",") || isValidOptionString(optionsPart) {
                parseOptions(
                    optionsPart,
                    resourceTypes: &resourceTypes,
                    loadType: &loadType,
                    includeDomains: &includeDomains,
                    excludeDomains: &excludeDomains,
                    matchCase: &matchCase
                )
            } else {
                // Put it back - it's not options
                pattern = line
            }
        }

        // Empty pattern after parsing
        guard !pattern.isEmpty else { return nil }

        // Parse anchors
        if pattern.hasPrefix("||") {
            isDomainAnchor = true
            pattern = String(pattern.dropFirst(2))
        } else if pattern.hasPrefix("|") {
            isAddressStartAnchor = true
            pattern = String(pattern.dropFirst())
        }

        if pattern.hasSuffix("|") {
            isAddressEndAnchor = true
            pattern = String(pattern.dropLast())
        }

        // Skip empty patterns
        guard !pattern.isEmpty else { return nil }

        // Skip overly broad patterns
        if pattern == "*" || pattern == "^" {
            return nil
        }

        return URLBlockRule(
            pattern: pattern,
            resourceTypes: resourceTypes,
            loadType: loadType,
            includeDomains: includeDomains,
            excludeDomains: excludeDomains,
            isDomainAnchor: isDomainAnchor,
            isAddressStartAnchor: isAddressStartAnchor,
            isAddressEndAnchor: isAddressEndAnchor,
            matchCase: matchCase
        )
    }

    private func isValidOptionString(_ str: String) -> Bool {
        let validOptions = [
            "third-party", "first-party", "3p", "1p",
            "script", "image", "stylesheet", "css", "font", "media",
            "xmlhttprequest", "xhr", "websocket", "document", "subdocument",
            "popup", "other", "domain", "match-case", "important",
            "~third-party", "~first-party", "~3p", "~1p",
            "~script", "~image", "~stylesheet", "~css", "~font", "~media"
        ]

        let options = str.lowercased().components(separatedBy: ",")
        for option in options {
            let trimmed = option.trimmingCharacters(in: .whitespaces)
            let isValid = validOptions.contains { trimmed.hasPrefix($0) }
            if isValid {
                return true
            }
        }
        return false
    }

    private func parseOptions(
        _ optionsString: String,
        resourceTypes: inout Set<ABPResourceType>,
        loadType: inout ABPLoadType,
        includeDomains: inout [String],
        excludeDomains: inout [String],
        matchCase: inout Bool
    ) {
        let options = optionsString.components(separatedBy: ",")

        for option in options {
            let trimmed = option.trimmingCharacters(in: .whitespaces).lowercased()

            // Negation prefix
            let isNegated = trimmed.hasPrefix("~")
            let optionName = isNegated ? String(trimmed.dropFirst()) : trimmed

            // Load types
            switch optionName {
            case "third-party", "3p":
                loadType = isNegated ? .firstParty : .thirdParty
            case "first-party", "1p":
                loadType = isNegated ? .thirdParty : .firstParty

            // Resource types
            case "script":
                handleResourceType(.script, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "image":
                handleResourceType(.image, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "stylesheet", "css":
                handleResourceType(.stylesheet, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "font":
                handleResourceType(.font, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "media":
                handleResourceType(.media, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "xmlhttprequest", "xhr":
                handleResourceType(.xmlhttprequest, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "websocket":
                handleResourceType(.websocket, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "document":
                handleResourceType(.document, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "subdocument":
                handleResourceType(.subdocument, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "popup":
                handleResourceType(.popup, isNegated: isNegated, resourceTypes: &resourceTypes)
            case "other":
                handleResourceType(.other, isNegated: isNegated, resourceTypes: &resourceTypes)

            // Match case
            case "match-case":
                matchCase = !isNegated

            default:
                // Domain restrictions
                if optionName.hasPrefix("domain=") {
                    let domainsStr = String(option.dropFirst("domain=".count + (isNegated ? 1 : 0)))
                    let domains = domainsStr.components(separatedBy: "|")

                    for domain in domains {
                        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
                        if trimmedDomain.hasPrefix("~") {
                            excludeDomains.append(String(trimmedDomain.dropFirst()))
                        } else {
                            includeDomains.append(trimmedDomain)
                        }
                    }
                }
            }
        }
    }

    private func handleResourceType(
        _ type: ABPResourceType,
        isNegated: Bool,
        resourceTypes: inout Set<ABPResourceType>
    ) {
        if isNegated {
            // If negated and we haven't added any types yet, add all then remove
            if resourceTypes.isEmpty {
                resourceTypes = Set(ABPResourceType.allCases)
            }
            resourceTypes.remove(type)
        } else {
            resourceTypes.insert(type)
        }
    }

    // MARK: - CSS Rule Parsing

    private func parseCSSHide(_ line: String, separatorRange: Range<String.Index>) -> ABPRule {
        let domainsPart = String(line[..<separatorRange.lowerBound])
        let selector = String(line[separatorRange.upperBound...])

        guard !selector.isEmpty else {
            return .unsupported(line)
        }

        var includeDomains: [String] = []
        var excludeDomains: [String] = []

        if !domainsPart.isEmpty {
            let domains = domainsPart.components(separatedBy: ",")
            for domain in domains {
                let trimmed = domain.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("~") {
                    excludeDomains.append(String(trimmed.dropFirst()))
                } else {
                    includeDomains.append(trimmed)
                }
            }
        }

        return .cssHide(CSSHideRule(
            selector: selector,
            includeDomains: includeDomains,
            excludeDomains: excludeDomains
        ))
    }

    private func parseCSSException(_ line: String, separatorRange: Range<String.Index>) -> ABPRule {
        let domainsPart = String(line[..<separatorRange.lowerBound])
        let selector = String(line[separatorRange.upperBound...])

        guard !selector.isEmpty else {
            return .unsupported(line)
        }

        var includeDomains: [String] = []
        var excludeDomains: [String] = []

        if !domainsPart.isEmpty {
            let domains = domainsPart.components(separatedBy: ",")
            for domain in domains {
                let trimmed = domain.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("~") {
                    excludeDomains.append(String(trimmed.dropFirst()))
                } else {
                    includeDomains.append(trimmed)
                }
            }
        }

        return .cssException(CSSHideRule(
            selector: selector,
            includeDomains: includeDomains,
            excludeDomains: excludeDomains
        ))
    }
}

// MARK: - Parser Statistics

extension ABPParser {
    /// Parse content and return statistics about the rules
    func parseWithStats(_ content: String) async -> (rules: [ABPRule], stats: ParserStats) {
        let rules = await parse(content)

        var stats = ParserStats()

        for rule in rules {
            switch rule {
            case .urlBlock:
                stats.urlBlockRules += 1
            case .urlException:
                stats.urlExceptionRules += 1
            case .cssHide:
                stats.cssHideRules += 1
            case .cssException:
                stats.cssExceptionRules += 1
            case .comment:
                stats.comments += 1
            case .unsupported:
                stats.unsupported += 1
            }
        }

        return (rules, stats)
    }

    struct ParserStats {
        var urlBlockRules: Int = 0
        var urlExceptionRules: Int = 0
        var cssHideRules: Int = 0
        var cssExceptionRules: Int = 0
        var comments: Int = 0
        var unsupported: Int = 0

        var totalRules: Int {
            urlBlockRules + urlExceptionRules + cssHideRules + cssExceptionRules
        }
    }
}
