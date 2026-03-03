import Foundation
import WebKit

/// Manages scriptlet injection for anti-adblock defusing.
///
/// Reads `##+js()` directives from parsed filter lists and generates a WKUserScript
/// containing the scriptlet library plus domain-specific invocations.
/// Injected at `.atDocumentStart` so scriptlets run before any page JavaScript.
@MainActor
class ScriptletInjector {

    static let shared = ScriptletInjector()

    /// Cached user script
    private var cachedScript: WKUserScript?

    private init() {}

    /// Generate a WKUserScript containing all applicable scriptlets
    func createUserScript() -> WKUserScript? {
        if let cached = cachedScript { return cached }

        let rules = FilterListManager.shared.getAllScriptletRules()
        guard !rules.isEmpty else { return nil }

        let script = buildScript(from: rules)
        guard !script.isEmpty else { return nil }

        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        cachedScript = userScript
        return userScript
    }

    /// Invalidate the cached script (call when filter lists change)
    func invalidateCache() {
        cachedScript = nil
    }

    // MARK: - Script Generation

    private func buildScript(from rules: [ScriptletRule]) -> String {
        // Group rules by domain for efficient matching
        let rulesJSON = serializeRules(rules)

        return """
        (function() {
            'use strict';
            if (window.__wheelScriptlets) return;
            if (window.__wheelAllowlisted) return;

            var RULES = \(rulesJSON);
            var host = window.location.hostname.toLowerCase();

            // Check if a domain matches (including parent domain matching)
            function domainMatches(domain, pattern) {
                return domain === pattern || domain.endsWith('.' + pattern);
            }

            function shouldApply(rule) {
                if (rule.inc.length > 0) {
                    var matched = false;
                    for (var i = 0; i < rule.inc.length; i++) {
                        if (domainMatches(host, rule.inc[i])) { matched = true; break; }
                    }
                    if (!matched) return false;
                }
                for (var j = 0; j < rule.exc.length; j++) {
                    if (domainMatches(host, rule.exc[j])) return false;
                }
                return true;
            }

            \(Self.scriptletLibrary)

            // Apply matching scriptlets
            var applied = 0;
            for (var i = 0; i < RULES.length; i++) {
                var rule = RULES[i];
                if (!shouldApply(rule)) continue;
                var fn = SCRIPTLETS[rule.name];
                if (fn) {
                    try { fn.apply(null, rule.args); applied++; } catch(e) {}
                }
            }

            window.__wheelScriptlets = { applied: applied };

            if (applied > 0 && window.__wheelBlockingStats) {
                for (var k = 0; k < applied; k++) {
                    window.__wheelBlockingStats.reportScriptletBlock();
                }
            }
        })();
        """
    }

    private func serializeRules(_ rules: [ScriptletRule]) -> String {
        let entries = rules.map { rule -> [String: Any] in
            [
                "name": rule.scriptletName,
                "args": rule.args,
                "inc": rule.includeDomains,
                "exc": rule.excludeDomains
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Scriptlet Library

    private static let scriptletLibrary = """
    var SCRIPTLETS = {
        'abort-on-property-read': function(prop) {
            if (!prop) return;
            var chain = prop.split('.');
            var owner = window;
            for (var i = 0; i < chain.length - 1; i++) {
                if (!owner[chain[i]]) owner[chain[i]] = {};
                owner = owner[chain[i]];
            }
            var last = chain[chain.length - 1];
            Object.defineProperty(owner, last, {
                get: function() { throw new ReferenceError(prop); },
                set: function() {}
            });
        },

        'abort-on-property-write': function(prop) {
            if (!prop) return;
            var chain = prop.split('.');
            var owner = window;
            for (var i = 0; i < chain.length - 1; i++) {
                if (!owner[chain[i]]) owner[chain[i]] = {};
                owner = owner[chain[i]];
            }
            var last = chain[chain.length - 1];
            Object.defineProperty(owner, last, {
                get: function() { return undefined; },
                set: function() { throw new ReferenceError(prop); }
            });
        },

        'set-constant': function(prop, value) {
            if (!prop) return;
            var realValue;
            switch (value) {
                case 'true': realValue = true; break;
                case 'false': realValue = false; break;
                case 'null': realValue = null; break;
                case 'undefined': realValue = undefined; break;
                case 'noopFunc': realValue = function() {}; break;
                case 'trueFunc': realValue = function() { return true; }; break;
                case 'falseFunc': realValue = function() { return false; }; break;
                case '': realValue = ''; break;
                default: realValue = isNaN(value) ? value : Number(value); break;
            }
            var chain = prop.split('.');
            var owner = window;
            for (var i = 0; i < chain.length - 1; i++) {
                if (!owner[chain[i]]) owner[chain[i]] = {};
                owner = owner[chain[i]];
            }
            var last = chain[chain.length - 1];
            try {
                Object.defineProperty(owner, last, {
                    get: function() { return realValue; },
                    set: function() {},
                    configurable: false
                });
            } catch(e) {
                owner[last] = realValue;
            }
        },

        'no-setTimeout-if': function(needle, delay) {
            var origST = window.setTimeout;
            window.setTimeout = function(cb, ms) {
                var cbStr = typeof cb === 'function' ? cb.toString() : String(cb);
                if (needle && cbStr.indexOf(needle) !== -1) return;
                if (delay && String(ms) === String(delay)) return;
                return origST.apply(this, arguments);
            };
        },

        'no-setInterval-if': function(needle, delay) {
            var origSI = window.setInterval;
            window.setInterval = function(cb, ms) {
                var cbStr = typeof cb === 'function' ? cb.toString() : String(cb);
                if (needle && cbStr.indexOf(needle) !== -1) return;
                if (delay && String(ms) === String(delay)) return;
                return origSI.apply(this, arguments);
            };
        },

        'no-xhr-if': function(urlNeedle) {
            if (!urlNeedle) return;
            var origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (typeof url === 'string' && url.indexOf(urlNeedle) !== -1) {
                    this.__wheelBlocked = true;
                    return;
                }
                return origOpen.apply(this, arguments);
            };
            var origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
                if (this.__wheelBlocked) return;
                return origSend.apply(this, arguments);
            };
        },

        'no-fetch-if': function(urlNeedle) {
            if (!urlNeedle) return;
            var origFetch = window.fetch;
            window.fetch = function(input) {
                var url = typeof input === 'string' ? input : (input && input.url) || '';
                if (url.indexOf(urlNeedle) !== -1) {
                    return Promise.resolve(new Response('', { status: 200 }));
                }
                return origFetch.apply(this, arguments);
            };
        },

        'prevent-addEventListener': function(type, needle) {
            var origAdd = EventTarget.prototype.addEventListener;
            EventTarget.prototype.addEventListener = function(evtType, handler, opts) {
                if (evtType === type) {
                    if (!needle) return;
                    if (handler && handler.toString().indexOf(needle) !== -1) return;
                }
                return origAdd.call(this, evtType, handler, opts);
            };
        },

        'window.open-defuser': function() {
            window.open = function() { return null; };
        },

        'prevent-eval-if': function(needle) {
            var origEval = window.eval;
            window.eval = function(code) {
                if (typeof code === 'string' && code.indexOf(needle) !== -1) return;
                return origEval.call(this, code);
            };
        },

        'json-prune': function(rawPaths) {
            if (!rawPaths) return;
            var paths = rawPaths.split(' ');
            var origParse = JSON.parse;
            JSON.parse = function() {
                var r = origParse.apply(this, arguments);
                if (r && typeof r === 'object') {
                    for (var i = 0; i < paths.length; i++) {
                        var chain = paths[i].split('.');
                        var obj = r;
                        for (var j = 0; j < chain.length - 1; j++) {
                            if (!obj || typeof obj !== 'object') break;
                            obj = obj[chain[j]];
                        }
                        if (obj && typeof obj === 'object') {
                            delete obj[chain[chain.length - 1]];
                        }
                    }
                }
                return r;
            };
        },

        'disable-newtab-links': function() {
            document.addEventListener('click', function(e) {
                var a = e.target.closest('a[target="_blank"]');
                if (a) a.removeAttribute('target');
            }, true);
        },

        'nowebrtc': function() {
            window.RTCPeerConnection = undefined;
            window.webkitRTCPeerConnection = undefined;
        }
    };
    """
}
