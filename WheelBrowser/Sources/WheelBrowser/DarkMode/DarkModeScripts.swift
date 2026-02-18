import Foundation

/// JavaScript bundle for dark mode functionality
struct DarkModeScripts {

    /// Generate the complete dark mode JavaScript bundle
    /// - Parameters:
    ///   - enabled: Whether dark mode should be enabled initially
    ///   - brightness: Brightness level (0-200)
    ///   - contrast: Contrast level (0-200)
    /// - Returns: JavaScript code to inject
    static func generateBundle(enabled: Bool, brightness: Double = 100, contrast: Double = 100) -> String {
        let css = DarkModeCSS.generateMinified(brightness: brightness, contrast: contrast)
        let enabledString = enabled ? "true" : "false"

        return """
        (function() {
            'use strict';

            // Prevent double initialization per page load
            if (window.__wheelDarkMode && window.__wheelDarkMode._initialized) return;

            const STYLE_ID = 'wheel-dark-mode-style';
            const DATA_ATTR = 'data-wheel-dark';

            // CSS for dark mode - embedded directly
            const darkModeCSS = `\(css)`;

            // State
            let isEnabled = \(enabledString);

            // Inject CSS immediately - don't wait for DOM
            // This runs at document_start so we inject into documentElement directly
            function injectStyleImmediate() {
                // Check if already injected
                if (document.getElementById(STYLE_ID)) return;

                try {
                    const style = document.createElement('style');
                    style.id = STYLE_ID;
                    style.textContent = darkModeCSS;

                    // At document_start, document.head doesn't exist yet
                    // Insert as first child of documentElement (html)
                    const target = document.head || document.documentElement;
                    if (target) {
                        // Insert at the very beginning to ensure highest priority
                        target.insertBefore(style, target.firstChild);
                    }
                } catch (e) {
                    // CSP might block style element - try adoptedStyleSheets as fallback
                    try {
                        if (document.adoptedStyleSheets !== undefined) {
                            const sheet = new CSSStyleSheet();
                            sheet.replaceSync(darkModeCSS);
                            document.adoptedStyleSheets = [sheet, ...document.adoptedStyleSheets];
                        }
                    } catch (e2) {
                        // Last resort: inline style on html element (limited but works)
                        console.warn('[WheelDarkMode] Style injection blocked, using inline fallback');
                    }
                }
            }

            // Apply dark mode attribute to html element
            function applyDarkAttribute() {
                if (document.documentElement) {
                    document.documentElement.setAttribute(DATA_ATTR, 'true');
                }
            }

            // Remove dark mode attribute
            function removeDarkAttribute() {
                if (document.documentElement) {
                    document.documentElement.removeAttribute(DATA_ATTR);
                }
            }

            // Enable dark mode
            function enable() {
                isEnabled = true;
                injectStyleImmediate();
                applyDarkAttribute();
            }

            // Disable dark mode
            function disable() {
                isEnabled = false;
                removeDarkAttribute();
                // Don't remove the style element - it's harmless without the attribute
            }

            // Toggle dark mode
            function toggle() {
                if (isEnabled) {
                    disable();
                } else {
                    enable();
                }
                return isEnabled;
            }

            // Check if dark mode is enabled
            function isActive() {
                return isEnabled;
            }

            // Update CSS with new brightness/contrast values
            function updateCSS(newCSS) {
                const style = document.getElementById(STYLE_ID);
                if (style) {
                    style.textContent = newCSS;
                }
            }

            // Initialize
            function init() {
                // Inject style element IMMEDIATELY - this is critical for preventing flash
                injectStyleImmediate();

                // Apply attribute if enabled
                if (isEnabled) {
                    applyDarkAttribute();
                }

                // Re-ensure after head is available (some sites manipulate early DOM)
                const ensureStyle = function() {
                    if (!document.getElementById(STYLE_ID)) {
                        injectStyleImmediate();
                    }
                    if (isEnabled && document.documentElement) {
                        applyDarkAttribute();
                    }
                };

                // Multiple fallbacks for different loading stages
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', ensureStyle, { once: true });
                }

                // Also check after full load (catches late DOM manipulation)
                window.addEventListener('load', ensureStyle, { once: true });

                // Lightweight observer - only watches for style element removal
                // Much more performant than watching all DOM changes
                let observerStarted = false;
                const startObserver = function() {
                    if (observerStarted || !document.head) return;
                    observerStarted = true;

                    const observer = new MutationObserver(function(mutations) {
                        if (!isEnabled) return;

                        // Only check if our style was removed
                        for (const mutation of mutations) {
                            for (const removed of mutation.removedNodes) {
                                if (removed.id === STYLE_ID) {
                                    injectStyleImmediate();
                                    return;
                                }
                            }
                        }
                    });

                    observer.observe(document.head, {
                        childList: true,
                        subtree: false  // Only direct children, not deep
                    });
                };

                if (document.head) {
                    startObserver();
                } else {
                    document.addEventListener('DOMContentLoaded', startObserver, { once: true });
                }
            }

            // Expose API
            window.__wheelDarkMode = {
                enable: enable,
                disable: disable,
                toggle: toggle,
                isActive: isActive,
                updateCSS: updateCSS,
                _initialized: true
            };

            // Run initialization
            init();
        })();
        """
    }

    /// Generate JavaScript to enable dark mode on an existing page
    static func enableScript(brightness: Double? = nil, contrast: Double? = nil) -> String {
        let b = brightness ?? AppSettings.shared.darkModeBrightness
        let c = contrast ?? AppSettings.shared.darkModeContrast
        let css = DarkModeCSS.generateMinified(brightness: b, contrast: c)
        return """
        (function() {
            if (window.__wheelDarkMode) {
                window.__wheelDarkMode.enable();
                // Also update CSS in case brightness/contrast changed
                window.__wheelDarkMode.updateCSS(`\(css)`);
            } else {
                // Fallback: inject styles and apply attribute if API not ready
                // This handles cases where the initial script failed
                const STYLE_ID = 'wheel-dark-mode-style';
                if (!document.getElementById(STYLE_ID)) {
                    try {
                        const style = document.createElement('style');
                        style.id = STYLE_ID;
                        style.textContent = `\(css)`;
                        const target = document.head || document.documentElement;
                        if (target) target.insertBefore(style, target.firstChild);
                    } catch(e) {
                        // Try adoptedStyleSheets
                        try {
                            if (document.adoptedStyleSheets !== undefined) {
                                const sheet = new CSSStyleSheet();
                                sheet.replaceSync(`\(css)`);
                                document.adoptedStyleSheets = [sheet, ...document.adoptedStyleSheets];
                            }
                        } catch(e2) {}
                    }
                }
                document.documentElement.setAttribute('data-wheel-dark', 'true');
            }
        })();
        """
    }

    /// Generate JavaScript to disable dark mode on an existing page
    static func disableScript() -> String {
        return """
        (function() {
            if (window.__wheelDarkMode) {
                window.__wheelDarkMode.disable();
            } else {
                document.documentElement.removeAttribute('data-wheel-dark');
            }
        })();
        """
    }

    /// Generate JavaScript to toggle dark mode on an existing page
    static func toggleScript() -> String {
        return """
        (function() {
            if (window.__wheelDarkMode) {
                return window.__wheelDarkMode.toggle();
            }
            return false;
        })();
        """
    }

    /// Generate JavaScript to update CSS with new brightness/contrast
    static func updateCSSScript(brightness: Double, contrast: Double) -> String {
        let css = DarkModeCSS.generateMinified(brightness: brightness, contrast: contrast)
        return """
        (function() {
            if (window.__wheelDarkMode) {
                window.__wheelDarkMode.updateCSS(`\(css)`);
            } else {
                // Fallback: update style directly
                const style = document.getElementById('wheel-dark-mode-style');
                if (style) style.textContent = `\(css)`;
            }
        })();
        """
    }
}
