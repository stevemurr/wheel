import Foundation

struct ABPConversionResult {
    let encodedRuleList: String
    let ruleCount: Int
    let skippedRuleCount: Int
    let diagnostics: [String]
}

enum ABPFilterRuleConverter {
    private static let supportedResourceTypes: [String: String] = [
        "document": "document",
        "subdocument": "document",
        "image": "image",
        "stylesheet": "style-sheet",
        "script": "script",
        "font": "font",
        "media": "media",
        "xmlhttprequest": "raw"
    ]

    private static let ignoredOptions: Set<String> = [
        "important"
    ]

    private static let unsupportedOptions: Set<String> = [
        "badfilter",
        "csp",
        "denyallow",
        "elemhide",
        "genericblock",
        "generichide",
        "match-case",
        "other",
        "ping",
        "popup",
        "redirect",
        "redirect-rule",
        "removeparam",
        "rewrite",
        "sitekey",
        "websocket"
    ]

    static func convert(
        filterText: String,
        allowlistedDomains: [String],
        maxRuleCount: Int = 50_000
    ) -> ABPConversionResult {
        var rules: [ContentBlockerRule] = []
        var diagnostics: [String] = []
        var skippedRuleCount = 0
        let normalizedAllowlist = allowlistedDomains.flatMap(domainTokens(for:))

        for rawLine in filterText.components(separatedBy: .newlines) {
            guard rules.count < maxRuleCount else {
                diagnostics.append("Reached max supported rule count of \(maxRuleCount).")
                break
            }

            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard shouldProcess(line) else { continue }

            if let rule = makeCosmeticRule(from: line, allowlistedDomains: normalizedAllowlist, diagnostics: &diagnostics) {
                rules.append(rule)
                continue
            }

            if let rule = makeNetworkRule(from: line, allowlistedDomains: normalizedAllowlist, diagnostics: &diagnostics) {
                rules.append(rule)
                continue
            }

            skippedRuleCount += 1
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(rules)) ?? Data("[]".utf8)
        let encoded = String(decoding: data, as: UTF8.self)

        return ABPConversionResult(
            encodedRuleList: encoded,
            ruleCount: rules.count,
            skippedRuleCount: skippedRuleCount,
            diagnostics: Array(diagnostics.prefix(20))
        )
    }

    private static func shouldProcess(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.hasPrefix("!") || line.hasPrefix("[") {
            return false
        }
        return true
    }

    private static func makeCosmeticRule(
        from line: String,
        allowlistedDomains: [String],
        diagnostics: inout [String]
    ) -> ContentBlockerRule? {
        if line.contains("#@#") || line.contains("##+js") || line.contains("#$#") || line.contains("#%#") {
            diagnostics.append("Skipped unsupported cosmetic rule: \(line)")
            return nil
        }

        guard let range = line.range(of: "##") else { return nil }

        let domainPart = String(line[..<range.lowerBound])
        let selector = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else {
            diagnostics.append("Skipped empty cosmetic selector.")
            return nil
        }

        let domainSplit = splitDomainFilters(domainPart)
        return ContentBlockerRule(
            trigger: Trigger(
                urlFilter: ".*",
                ifDomain: domainSplit.ifDomains.isEmpty ? nil : domainSplit.ifDomains,
                unlessDomain: mergeDomains(domainSplit.unlessDomains, allowlistedDomains),
                resourceType: nil,
                loadType: nil
            ),
            action: Action(type: "css-display-none", selector: selector)
        )
    }

    private static func makeNetworkRule(
        from line: String,
        allowlistedDomains: [String],
        diagnostics: inout [String]
    ) -> ContentBlockerRule? {
        var workingLine = line
        let isException = workingLine.hasPrefix("@@")
        if isException {
            workingLine.removeFirst(2)
        }

        let parts = workingLine.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(parts[0])
        guard !pattern.isEmpty else {
            diagnostics.append("Skipped rule with empty pattern.")
            return nil
        }

        let options = parts.count == 2
            ? String(parts[1]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            : []

        let parsedOptions = parseOptions(options, diagnostics: &diagnostics)
        guard parsedOptions.isSupported else { return nil }

        return ContentBlockerRule(
            trigger: Trigger(
                urlFilter: convertPatternToRegex(pattern),
                ifDomain: parsedOptions.ifDomains.isEmpty ? nil : parsedOptions.ifDomains,
                unlessDomain: mergeDomains(parsedOptions.unlessDomains, allowlistedDomains),
                resourceType: parsedOptions.resourceTypes.isEmpty ? nil : parsedOptions.resourceTypes,
                loadType: parsedOptions.loadTypes.isEmpty ? nil : parsedOptions.loadTypes
            ),
            action: Action(type: isException ? "ignore-previous-rules" : "block", selector: nil)
        )
    }

    private static func parseOptions(
        _ options: [String],
        diagnostics: inout [String]
    ) -> ParsedOptions {
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        var resourceTypes: [String] = []
        var loadTypes: [String] = []

        for option in options where !option.isEmpty {
            if ignoredOptions.contains(option) {
                continue
            }
            if unsupportedOptions.contains(option) {
                diagnostics.append("Skipped unsupported filter option: \(option)")
                return ParsedOptions(isSupported: false)
            }

            if option == "third-party" {
                loadTypes = ["third-party"]
                continue
            }

            if option == "~third-party" || option == "first-party" {
                loadTypes = ["first-party"]
                continue
            }

            if let mappedType = supportedResourceTypes[option] {
                if !resourceTypes.contains(mappedType) {
                    resourceTypes.append(mappedType)
                }
                continue
            }

            if let domainExpression = option.split(separator: "=", maxSplits: 1).map(String.init).second,
               option.hasPrefix("domain=") {
                let parsedDomains = splitDomainFilters(domainExpression.replacingOccurrences(of: "|", with: ","))
                ifDomains.append(contentsOf: parsedDomains.ifDomains)
                unlessDomains.append(contentsOf: parsedDomains.unlessDomains)
                continue
            }

            diagnostics.append("Skipped unsupported filter option: \(option)")
            return ParsedOptions(isSupported: false)
        }

        return ParsedOptions(
            isSupported: true,
            ifDomains: dedupe(ifDomains),
            unlessDomains: dedupe(unlessDomains),
            resourceTypes: dedupe(resourceTypes),
            loadTypes: dedupe(loadTypes)
        )
    }

    private static func splitDomainFilters(_ rawValue: String) -> (ifDomains: [String], unlessDomains: [String]) {
        let tokens = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var ifDomains: [String] = []
        var unlessDomains: [String] = []

        for token in tokens {
            if token.hasPrefix("~") {
                unlessDomains.append(contentsOf: domainTokens(for: String(token.dropFirst())))
            } else {
                ifDomains.append(contentsOf: domainTokens(for: token))
            }
        }

        return (dedupe(ifDomains), dedupe(unlessDomains))
    }

    private static func domainTokens(for rawDomain: String) -> [String] {
        let domain = rawDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !domain.isEmpty else { return [] }
        return dedupe([domain, "*\(domain)"])
    }

    private static func mergeDomains(_ lhs: [String], _ rhs: [String]) -> [String]? {
        let merged = dedupe(lhs + rhs)
        return merged.isEmpty ? nil : merged
    }

    private static func convertPatternToRegex(_ pattern: String) -> String {
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1 {
            return String(pattern.dropFirst().dropLast())
        }

        var working = pattern
        var isDomainAnchored = false
        var anchorStart = false
        var anchorEnd = false

        if working.hasPrefix("||") {
            isDomainAnchored = true
            working.removeFirst(2)
        } else if working.hasPrefix("|") {
            anchorStart = true
            working.removeFirst()
        }

        if working.hasSuffix("|") {
            anchorEnd = true
            working.removeLast()
        }

        let translated = working.reduce(into: "") { partialResult, character in
            switch character {
            case "*":
                partialResult += ".*"
            case "^":
                partialResult += "[^A-Za-z0-9_\\-.%]"
            default:
                let scalar = String(character)
                if "\\.+?()[]{}|^$".contains(character) {
                    partialResult += "\\\(scalar)"
                } else {
                    partialResult += scalar
                }
            }
        }

        var regex = translated
        if isDomainAnchored {
            regex = "^[^:]+://([^/]+\\.)?" + translated
        } else if anchorStart {
            regex = "^" + translated
        }
        if anchorEnd {
            regex += "$"
        }
        return regex
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

private struct ParsedOptions {
    var isSupported: Bool
    var ifDomains: [String] = []
    var unlessDomains: [String] = []
    var resourceTypes: [String] = []
    var loadTypes: [String] = []
}

private struct ContentBlockerRule: Encodable {
    let trigger: Trigger
    let action: Action
}

private struct Trigger: Encodable {
    let urlFilter: String
    let ifDomain: [String]?
    let unlessDomain: [String]?
    let resourceType: [String]?
    let loadType: [String]?

    enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
        case ifDomain = "if-domain"
        case unlessDomain = "unless-domain"
        case resourceType = "resource-type"
        case loadType = "load-type"
    }
}

private struct Action: Encodable {
    let type: String
    let selector: String?
}

private extension Array {
    var second: Element? {
        guard count > 1 else { return nil }
        return self[1]
    }
}
