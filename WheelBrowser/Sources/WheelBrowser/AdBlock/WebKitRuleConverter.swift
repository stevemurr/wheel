import Foundation

// MARK: - WebKit Rule Converter

/// Converts parsed ABP rules to WebKit Content Blocker JSON format
struct WebKitRuleConverter {

    /// Maximum number of rules WebKit can handle per content blocker
    static let maxRulesPerList = 50_000

    /// Convert an array of ABP rules to WebKit JSON format
    /// - Parameters:
    ///   - rules: Array of parsed ABP rules
    ///   - maxRules: Maximum number of rules to convert (default: 50,000)
    /// - Returns: Array of WebKit rule dictionaries
    func convert(_ rules: [ABPRule], maxRules: Int = maxRulesPerList) -> [[String: Any]] {
        var webkitRules: [[String: Any]] = []

        for rule in rules {
            // Stop if we've hit the max
            guard webkitRules.count < maxRules else { break }

            switch rule {
            case .urlBlock(let urlRule):
                if let converted = convertURLBlockRule(urlRule, isException: false) {
                    webkitRules.append(converted)
                }

            case .urlException(let urlRule):
                if let converted = convertURLBlockRule(urlRule, isException: true) {
                    webkitRules.append(converted)
                }

            case .cssHide(let cssRule):
                if let converted = convertCSSHideRule(cssRule, isException: false) {
                    webkitRules.append(converted)
                }

            case .cssException(let cssRule):
                if let converted = convertCSSHideRule(cssRule, isException: true) {
                    webkitRules.append(converted)
                }

            case .comment, .unsupported:
                // Skip comments and unsupported rules
                continue
            }
        }

        return webkitRules
    }

    // MARK: - URL Rule Conversion

    private func convertURLBlockRule(_ rule: URLBlockRule, isException: Bool) -> [String: Any]? {
        // Build the URL filter regex
        guard let urlFilter = buildURLFilter(from: rule) else {
            return nil
        }

        // Build trigger
        var trigger: [String: Any] = ["url-filter": urlFilter]

        // Add resource types if specified
        if !rule.resourceTypes.isEmpty {
            let webkitTypes = rule.resourceTypes.compactMap { $0.webkitType }
            if !webkitTypes.isEmpty {
                trigger["resource-type"] = webkitTypes
            }
        }

        // Add load type
        switch rule.loadType {
        case .thirdParty:
            trigger["load-type"] = ["third-party"]
        case .firstParty:
            trigger["load-type"] = ["first-party"]
        case .all:
            break // Don't add load-type for all
        }

        // Add domain conditions
        if !rule.includeDomains.isEmpty {
            trigger["if-domain"] = rule.includeDomains.map { "*\($0)" }
        }

        if !rule.excludeDomains.isEmpty {
            trigger["unless-domain"] = rule.excludeDomains.map { "*\($0)" }
        }

        // Add case sensitivity
        if rule.matchCase {
            trigger["url-filter-is-case-sensitive"] = true
        }

        // Build action
        let action: [String: Any]
        if isException {
            action = ["type": "ignore-previous-rules"]
        } else {
            action = ["type": "block"]
        }

        return [
            "trigger": trigger,
            "action": action
        ]
    }

    private func buildURLFilter(from rule: URLBlockRule) -> String? {
        var pattern = rule.pattern

        // Skip overly broad patterns
        if pattern == "*" || pattern.isEmpty {
            return nil
        }

        // Skip patterns that are just separators
        if pattern == "^" {
            return nil
        }

        // Skip patterns with complex regex that might fail
        if pattern.contains("(?") || pattern.contains("\\d") || pattern.contains("\\w") {
            return nil
        }

        // Convert ABP wildcards to regex BEFORE escaping
        // * -> .* (match anything)
        pattern = pattern.replacingOccurrences(of: "*", with: "{{WILDCARD}}")

        // ^ -> separator character (non-alphanumeric except _ - . %)
        pattern = pattern.replacingOccurrences(of: "^", with: "{{SEPARATOR}}")

        // Now escape regex special characters
        pattern = escapeRegexSpecials(pattern)

        // Replace placeholders with actual regex
        pattern = pattern.replacingOccurrences(of: "{{WILDCARD}}", with: ".*")
        pattern = pattern.replacingOccurrences(of: "{{SEPARATOR}}", with: "[^a-zA-Z0-9_.%-]")

        // Handle anchors
        if rule.isDomainAnchor {
            // || means start of domain
            // Match: https://domain.com or https://subdomain.domain.com
            // Use a simpler pattern that WebKit handles better
            pattern = "^https?://([^/]+\\.)?" + pattern
        } else if rule.isAddressStartAnchor {
            // | at start means beginning of address
            pattern = "^" + pattern
        }

        if rule.isAddressEndAnchor {
            // | at end means end of address
            pattern = pattern + "$"
        }

        // Skip patterns that are too long (can cause compilation issues)
        if pattern.count > 500 {
            return nil
        }

        // Validate the regex
        guard isValidRegex(pattern) else {
            return nil
        }

        return pattern
    }

    private func escapeRegexSpecials(_ pattern: String) -> String {
        // Characters that need escaping in regex, except * and ^ which have ABP meaning
        // Note: / is not a regex special character, don't escape it
        let specialChars = ["\\", ".", "+", "?", "{", "}", "[", "]", "(", ")", "|", "$"]

        var result = pattern
        for char in specialChars {
            result = result.replacingOccurrences(of: char, with: "\\\(char)")
        }

        return result
    }

    private func isValidRegex(_ pattern: String) -> Bool {
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return true
        } catch {
            return false
        }
    }

    // MARK: - CSS Rule Conversion

    private func convertCSSHideRule(_ rule: CSSHideRule, isException: Bool) -> [String: Any]? {
        // Validate selector - skip complex or potentially problematic selectors
        guard isValidSelector(rule.selector) else {
            return nil
        }

        // Build trigger - use a simple catch-all pattern
        var trigger: [String: Any] = ["url-filter": ".*"]

        // Add domain conditions only if specified
        // Don't use ["*"] as WebKit may reject it
        if !rule.includeDomains.isEmpty {
            trigger["if-domain"] = rule.includeDomains.map { "*\($0)" }
        }

        if !rule.excludeDomains.isEmpty {
            trigger["unless-domain"] = rule.excludeDomains.map { "*\($0)" }
        }

        // Build action
        let action: [String: Any]
        if isException {
            // Exception rules use ignore-previous-rules
            action = ["type": "ignore-previous-rules"]
        } else {
            action = [
                "type": "css-display-none",
                "selector": rule.selector
            ]
        }

        return [
            "trigger": trigger,
            "action": action
        ]
    }

    private func isValidSelector(_ selector: String) -> Bool {
        // Skip empty selectors
        guard !selector.isEmpty else { return false }

        // Skip selectors that are too long
        guard selector.count < 500 else { return false }

        // Skip selectors with :has() - not supported in WebKit content blockers
        if selector.contains(":has(") { return false }

        // Skip selectors with :is() or :where() - may not be supported
        if selector.contains(":is(") || selector.contains(":where(") { return false }

        // Skip selectors with :not() containing complex selectors
        if selector.contains(":not(") {
            // Check if :not() contains complex selector
            if let range = selector.range(of: ":not(") {
                let afterNot = selector[range.upperBound...]
                // Skip if contains nested pseudo-classes or combinators
                if afterNot.contains(":") || afterNot.contains(" ") || afterNot.contains(">") {
                    return false
                }
            }
        }

        // Skip selectors with procedural operators (ABP extended syntax)
        let proceduralOperators = [
            ":contains(", ":has-text(", ":xpath(", ":-abp-", ":matches-css(",
            ":style(", ":remove(", ":upward(", ":nth-ancestor("
        ]
        for op in proceduralOperators {
            if selector.contains(op) { return false }
        }

        // Skip selectors with invalid characters that might break JSON
        if selector.contains("\\") && !selector.contains("\\\\") {
            // Unescaped backslashes can cause JSON issues
            return false
        }

        return true
    }
}

// MARK: - Conversion Statistics

extension WebKitRuleConverter {

    /// Convert rules and return statistics
    func convertWithStats(_ rules: [ABPRule], maxRules: Int = WebKitRuleConverter.maxRulesPerList) -> (rules: [[String: Any]], stats: ConversionStats) {
        var webkitRules: [[String: Any]] = []
        var stats = ConversionStats()

        for rule in rules {
            guard webkitRules.count < maxRules else {
                stats.truncated = true
                break
            }

            switch rule {
            case .urlBlock(let urlRule):
                if let converted = convertURLBlockRule(urlRule, isException: false) {
                    webkitRules.append(converted)
                    stats.urlBlockConverted += 1
                } else {
                    stats.urlBlockFailed += 1
                }

            case .urlException(let urlRule):
                if let converted = convertURLBlockRule(urlRule, isException: true) {
                    webkitRules.append(converted)
                    stats.urlExceptionConverted += 1
                } else {
                    stats.urlExceptionFailed += 1
                }

            case .cssHide(let cssRule):
                if let converted = convertCSSHideRule(cssRule, isException: false) {
                    webkitRules.append(converted)
                    stats.cssHideConverted += 1
                } else {
                    stats.cssHideFailed += 1
                }

            case .cssException(let cssRule):
                if let converted = convertCSSHideRule(cssRule, isException: true) {
                    webkitRules.append(converted)
                    stats.cssExceptionConverted += 1
                } else {
                    stats.cssExceptionFailed += 1
                }

            case .comment:
                stats.comments += 1

            case .unsupported:
                stats.unsupported += 1
            }
        }

        return (webkitRules, stats)
    }

    struct ConversionStats {
        var urlBlockConverted: Int = 0
        var urlBlockFailed: Int = 0
        var urlExceptionConverted: Int = 0
        var urlExceptionFailed: Int = 0
        var cssHideConverted: Int = 0
        var cssHideFailed: Int = 0
        var cssExceptionConverted: Int = 0
        var cssExceptionFailed: Int = 0
        var comments: Int = 0
        var unsupported: Int = 0
        var truncated: Bool = false

        var totalConverted: Int {
            urlBlockConverted + urlExceptionConverted + cssHideConverted + cssExceptionConverted
        }

        var totalFailed: Int {
            urlBlockFailed + urlExceptionFailed + cssHideFailed + cssExceptionFailed
        }
    }
}
