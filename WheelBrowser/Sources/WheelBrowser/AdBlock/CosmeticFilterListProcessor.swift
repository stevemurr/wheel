import Foundation

/// Processed cosmetic filters organized for efficient injection
struct ProcessedCosmeticFilters: Codable {
    /// CSS selectors with no domain restriction (apply everywhere)
    var genericSelectors: [String] = []

    /// Domain-specific CSS selectors: domain -> [selectors]
    var domainSelectors: [String: [String]] = [:]

    /// Selectors excepted on certain domains: selector -> [excepted domains]
    var exceptionsBySelector: [String: Set<String>] = [:]

    var isEmpty: Bool {
        genericSelectors.isEmpty && domainSelectors.isEmpty
    }

    var totalSelectorCount: Int {
        genericSelectors.count + domainSelectors.values.reduce(0) { $0 + $1.count }
    }
}

/// Extracts CSS hide rules from parsed ABP rules and groups them for JS injection.
actor CosmeticFilterListProcessor {

    /// Process parsed ABP rules into domain-grouped cosmetic filters
    func process(_ rules: [ABPRule]) -> ProcessedCosmeticFilters {
        var result = ProcessedCosmeticFilters()

        for rule in rules {
            switch rule {
            case .cssHide(let cssRule):
                processCSSHide(cssRule, into: &result)
            case .cssException(let cssRule):
                processCSSException(cssRule, into: &result)
            default:
                break
            }
        }

        return result
    }

    /// Merge cosmetic filters from multiple filter lists
    func merge(_ filters: [ProcessedCosmeticFilters]) -> ProcessedCosmeticFilters {
        var merged = ProcessedCosmeticFilters()

        for filter in filters {
            // Merge generic selectors (deduplicate)
            let existingGeneric = Set(merged.genericSelectors)
            for selector in filter.genericSelectors where !existingGeneric.contains(selector) {
                merged.genericSelectors.append(selector)
            }

            // Merge domain selectors
            for (domain, selectors) in filter.domainSelectors {
                let existing = Set(merged.domainSelectors[domain] ?? [])
                let newSelectors = selectors.filter { !existing.contains($0) }
                merged.domainSelectors[domain, default: []].append(contentsOf: newSelectors)
            }

            // Merge exceptions
            for (selector, domains) in filter.exceptionsBySelector {
                merged.exceptionsBySelector[selector, default: []].formUnion(domains)
            }
        }

        return merged
    }

    // MARK: - Private

    private func processCSSHide(_ rule: CSSHideRule, into result: inout ProcessedCosmeticFilters) {
        let selector = rule.selector

        // Skip selectors that are too complex for safe CSS injection
        guard isValidForCosmeticFilter(selector) else { return }

        if rule.includeDomains.isEmpty && rule.excludeDomains.isEmpty {
            // Generic selector — applies everywhere
            result.genericSelectors.append(selector)
        } else {
            // Domain-specific selector
            if rule.includeDomains.isEmpty {
                // No include domains but has exclude domains — treat as generic with exceptions
                result.genericSelectors.append(selector)
                result.exceptionsBySelector[selector, default: []].formUnion(rule.excludeDomains)
            } else {
                for domain in rule.includeDomains {
                    result.domainSelectors[domain, default: []].append(selector)
                }
                if !rule.excludeDomains.isEmpty {
                    result.exceptionsBySelector[selector, default: []].formUnion(rule.excludeDomains)
                }
            }
        }
    }

    private func processCSSException(_ rule: CSSHideRule, into result: inout ProcessedCosmeticFilters) {
        let selector = rule.selector

        if rule.includeDomains.isEmpty {
            // Global exception — remove from generic selectors
            result.genericSelectors.removeAll { $0 == selector }
        } else {
            // Domain-specific exception
            result.exceptionsBySelector[selector, default: []].formUnion(rule.includeDomains)
        }
    }

    private func isValidForCosmeticFilter(_ selector: String) -> Bool {
        guard !selector.isEmpty, selector.count < 1000 else { return false }

        // Skip selectors with procedural operators
        let procedural = [":contains(", ":has-text(", ":xpath(", ":-abp-",
                          ":matches-css(", ":style(", ":remove(", ":upward(",
                          ":nth-ancestor("]
        for op in procedural {
            if selector.contains(op) { return false }
        }

        return true
    }
}
