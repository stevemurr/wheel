import Foundation
import WebKit

/// Builds WKUserScripts for cosmetic (element hiding) filters.
///
/// Two-stage approach:
/// 1. Early hiding: injects a `<style>` tag at document start with generic selectors
/// 2. Domain-aware filtering: at document end, applies domain-specific selectors
///    and sets up a MutationObserver for dynamically inserted ad containers
enum CosmeticFilterEngine {

    /// Creates a WKUserScript that injects CSS to hide elements matching generic selectors
    /// and domain-specific selectors, with a MutationObserver for dynamic content.
    static func createUserScript(from filters: ProcessedCosmeticFilters) -> WKUserScript? {
        guard !filters.isEmpty else { return nil }

        let script = buildScript(from: filters)
        guard !script.isEmpty else { return nil }

        return WKUserScript(
            source: script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    // MARK: - Script Generation

    private static func buildScript(from filters: ProcessedCosmeticFilters) -> String {
        let genericJSON = escapeForJS(filters.genericSelectors)
        let domainJSON = escapeDomainsForJS(filters.domainSelectors)
        let exceptionsJSON = escapeExceptionsForJS(filters.exceptionsBySelector)

        return """
        (function() {
            'use strict';
            if (window.__wheelCosmeticFilter) return;
            if (window.__wheelAllowlisted) return;

            var GENERIC = \(genericJSON);
            var DOMAINS = \(domainJSON);
            var EXCEPTIONS = \(exceptionsJSON);

            var host = window.location.hostname.toLowerCase();

            function getSelectorsForDomain(domain) {
                var selectors = GENERIC.slice();
                var parts = domain.split('.');
                for (var i = 0; i < parts.length - 1; i++) {
                    var candidate = parts.slice(i).join('.');
                    if (DOMAINS[candidate]) {
                        selectors = selectors.concat(DOMAINS[candidate]);
                    }
                }
                // Remove excepted selectors for this domain
                if (Object.keys(EXCEPTIONS).length > 0) {
                    selectors = selectors.filter(function(sel) {
                        var excDomains = EXCEPTIONS[sel];
                        if (!excDomains) return true;
                        for (var j = 0; j < excDomains.length; j++) {
                            if (domain === excDomains[j] || domain.endsWith('.' + excDomains[j])) {
                                return false;
                            }
                        }
                        return true;
                    });
                }
                return selectors;
            }

            function injectHidingStyle(selectors) {
                if (selectors.length === 0) return;
                var style = document.createElement('style');
                style.id = 'wheel-cosmetic-filter';
                style.textContent = selectors.join(',\\n') + ' { display: none !important; }';
                (document.head || document.documentElement).appendChild(style);
            }

            function observeDOM(selectors) {
                if (selectors.length === 0) return;
                var selectorStr = selectors.join(', ');
                var hiddenCount = 0;
                var observer = new MutationObserver(function(mutations) {
                    for (var i = 0; i < mutations.length; i++) {
                        var added = mutations[i].addedNodes;
                        for (var j = 0; j < added.length; j++) {
                            var node = added[j];
                            if (node.nodeType !== 1) continue;
                            try {
                                if (node.matches && node.matches(selectorStr)) {
                                    node.style.setProperty('display', 'none', 'important');
                                    hiddenCount++;
                                }
                                if (node.querySelectorAll) {
                                    var matches = node.querySelectorAll(selectorStr);
                                    for (var k = 0; k < matches.length; k++) {
                                        matches[k].style.setProperty('display', 'none', 'important');
                                        hiddenCount++;
                                    }
                                }
                            } catch(e) {}
                        }
                    }
                    if (hiddenCount > 0 && window.__wheelBlockingStats) {
                        window.__wheelBlockingStats.reportHidden(hiddenCount);
                        hiddenCount = 0;
                    }
                });
                observer.observe(document.documentElement, { childList: true, subtree: true });
                setTimeout(function() { observer.disconnect(); }, 30000);
            }

            var selectors = getSelectorsForDomain(host);
            injectHidingStyle(selectors);
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() { observeDOM(selectors); });
            } else {
                observeDOM(selectors);
            }

            window.__wheelCosmeticFilter = { count: selectors.length };
        })();
        """
    }

    // MARK: - JSON Helpers

    private static func escapeForJS(_ selectors: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: selectors),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func escapeDomainsForJS(_ domainSelectors: [String: [String]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: domainSelectors),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func escapeExceptionsForJS(_ exceptions: [String: Set<String>]) -> String {
        // Convert Set<String> to [String] for JSON serialization
        let converted = exceptions.mapValues { Array($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: converted),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
