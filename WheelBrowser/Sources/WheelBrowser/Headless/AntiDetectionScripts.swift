import WebKit

/// Anti-bot-detection scripts injected at document-start in headless mode.
/// Overrides browser APIs that sites use to detect automated browsing.
enum AntiDetectionScripts {

    /// Creates a WKUserScript that spoofs detection vectors.
    static func createUserScript() -> WKUserScript {
        return WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    private static let scriptSource = """
    (function() {
        'use strict';

        // --- Visibility API ---
        // macOS may report "hidden" for off-screen windows, causing sites to self-throttle.
        Object.defineProperty(document, 'visibilityState', {
            get: function() { return 'visible'; },
            configurable: true
        });
        Object.defineProperty(document, 'hidden', {
            get: function() { return false; },
            configurable: true
        });

        // Suppress visibilitychange events that macOS might fire
        var originalAddEventListener = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, listener, options) {
            if (type === 'visibilitychange' && this === document) {
                // Wrap listener to only fire when we want it to
                var wrappedListener = function(event) {
                    if (document.visibilityState === 'visible') {
                        return; // Suppress transitions to hidden
                    }
                    listener.call(this, event);
                };
                return originalAddEventListener.call(this, type, wrappedListener, options);
            }
            return originalAddEventListener.call(this, type, listener, options);
        };

        // --- Focus API ---
        // Accessory apps may not have focus; always report true.
        Document.prototype.hasFocus = function() { return true; };

        // --- WebDriver flag ---
        // WKWebView doesn't set this by default, but some pages check defensively.
        Object.defineProperty(navigator, 'webdriver', {
            get: function() { return undefined; },
            configurable: true
        });

        // --- Permissions API ---
        // Headless Chrome returns 'denied' instantly for notifications; real Safari returns 'prompt'.
        if (navigator.permissions) {
            var originalQuery = navigator.permissions.query.bind(navigator.permissions);
            navigator.permissions.query = function(descriptor) {
                if (descriptor && descriptor.name === 'notifications') {
                    return Promise.resolve({ state: 'prompt', onchange: null });
                }
                return originalQuery(descriptor);
            };
        }

        // --- Plugins ---
        // Safari always has at least the WebKit built-in PDF plugin.
        if (navigator.plugins.length === 0) {
            Object.defineProperty(navigator, 'plugins', {
                get: function() {
                    return {
                        length: 1,
                        0: { name: 'WebKit built-in PDF', filename: 'WebKitPDFPlugin', description: 'Portable Document Format' },
                        item: function(i) { return i === 0 ? this[0] : null; },
                        namedItem: function(name) { return name === 'WebKit built-in PDF' ? this[0] : null; },
                        refresh: function() {}
                    };
                },
                configurable: true
            });
        }

        // --- Languages ---
        // Ensure languages array is populated (Safari always has this).
        if (!navigator.languages || navigator.languages.length === 0) {
            Object.defineProperty(navigator, 'languages', {
                get: function() { return ['en-US', 'en']; },
                configurable: true
            });
        }

        // --- Performance timing jitter ---
        // Add micro-jitter (0-0.1ms) to defeat timing-based detection that looks
        // for unnaturally precise timestamps in automated environments.
        var originalNow = performance.now.bind(performance);
        performance.now = function() {
            return originalNow() + (Math.random() * 0.1);
        };

        // --- Chrome detection guard ---
        // We're Safari/WebKit — ensure window.chrome is not present.
        if (window.chrome) {
            delete window.chrome;
        }
    })();
    """
}
