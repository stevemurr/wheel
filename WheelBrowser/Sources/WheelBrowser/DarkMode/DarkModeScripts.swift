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
        let brightnessValue = brightness / 100.0
        let contrastValue = contrast / 100.0

        return """
        (function() {
            'use strict';

            // Prevent double initialization per page load
            if (window.__wheelDarkMode && window.__wheelDarkMode._initialized) return;

            const STYLE_ID = 'wheel-dark-mode-style';
            const DATA_ATTR = 'data-wheel-dark';
            const MODE_ATTR = 'data-wheel-dark-mode';

            // CSS for dark mode - embedded directly
            const darkModeCSS = `\(css)`;

            // State
            let isEnabled = \(enabledString);
            let detectedMode = 'filter'; // Always start with filter for reliability

            // Check if site actually has a dark background (native dark mode working)
            function checkIfBackgroundIsDark() {
                if (!document.body) return false;

                const bgColor = window.getComputedStyle(document.body).backgroundColor;
                if (!bgColor || bgColor === 'transparent' || bgColor === 'rgba(0, 0, 0, 0)') {
                    // Check html element instead
                    const htmlBg = window.getComputedStyle(document.documentElement).backgroundColor;
                    if (!htmlBg || htmlBg === 'transparent' || htmlBg === 'rgba(0, 0, 0, 0)') {
                        return false;
                    }
                    return isColorDark(htmlBg);
                }
                return isColorDark(bgColor);
            }

            // Parse RGB and check if it's dark (luminance < 0.5)
            function isColorDark(color) {
                const match = color.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
                if (!match) return false;

                const r = parseInt(match[1]) / 255;
                const g = parseInt(match[2]) / 255;
                const b = parseInt(match[3]) / 255;

                // Calculate relative luminance
                const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
                return luminance < 0.4; // Consider dark if luminance is below 40%
            }

            // Detect if site has working native dark mode
            function detectNativeDarkMode() {
                // First check: does the site already have a dark background?
                // This means it either already has dark mode or responds to color-scheme
                if (checkIfBackgroundIsDark()) {
                    return 'native';
                }

                // For sites with light backgrounds, we need filter mode
                return 'filter';
            }

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

            // Apply dark mode attribute and inline styles to html element
            function applyDarkAttribute() {
                console.log('[WheelDarkMode] applyDarkAttribute called, isEnabled:', isEnabled);

                if (document.documentElement) {
                    document.documentElement.setAttribute(DATA_ATTR, 'true');
                    document.documentElement.setAttribute(MODE_ATTR, 'filter');

                    // Apply inline styles for maximum specificity (overrides any CSS)
                    document.documentElement.style.setProperty('background-color', '#1a1a1a', 'important');
                    document.documentElement.style.setProperty('min-height', '100%', 'important');
                    console.log('[WheelDarkMode] Applied html background');
                }

                // Apply filter to body with inline styles for maximum specificity
                if (document.body) {
                    console.log('[WheelDarkMode] Body exists, applying filter');
                    applyFilterToBody();
                } else {
                    console.log('[WheelDarkMode] Body not ready, setting up observer');
                    // Body not ready yet, wait for it
                    const bodyObserver = new MutationObserver(function(mutations, obs) {
                        if (document.body) {
                            console.log('[WheelDarkMode] Body now exists via observer');
                            applyFilterToBody();
                            obs.disconnect();
                        }
                    });
                    bodyObserver.observe(document.documentElement, { childList: true });
                }
            }

            // Apply filter directly to body with inline style (highest specificity)
            function applyFilterToBody() {
                if (!document.body) {
                    console.log('[WheelDarkMode] applyFilterToBody: no body yet');
                    return;
                }
                if (!isEnabled) {
                    console.log('[WheelDarkMode] applyFilterToBody: not enabled');
                    return;
                }

                const brightness = \(brightnessValue);
                const contrast = \(contrastValue);
                const filterValue = 'invert(1) hue-rotate(180deg) brightness(' + brightness + ') contrast(' + contrast + ')';

                console.log('[WheelDarkMode] Applying filter to body:', filterValue);
                document.body.style.setProperty('filter', filterValue, 'important');
                document.body.style.setProperty('min-height', '100%', 'important');

                // Debug: verify it was applied
                const applied = document.body.style.filter;
                console.log('[WheelDarkMode] Body filter after apply:', applied);
            }

            // Remove dark mode attribute and inline styles
            function removeDarkAttribute() {
                if (document.documentElement) {
                    document.documentElement.removeAttribute(DATA_ATTR);
                    document.documentElement.removeAttribute(MODE_ATTR);
                    document.documentElement.style.removeProperty('background-color');
                    document.documentElement.style.removeProperty('min-height');
                }
                if (document.body) {
                    document.body.style.removeProperty('filter');
                    document.body.style.removeProperty('min-height');
                }
            }

            // Switch to native mode if site properly supports dark mode
            // This reduces filter artifacts on sites with good native support
            function switchToNativeIfSupported() {
                if (!isEnabled || !document.documentElement) return;

                // Only switch if background is actually dark
                if (checkIfBackgroundIsDark()) {
                    detectedMode = 'native';
                    document.documentElement.setAttribute(MODE_ATTR, 'native');
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

            // Get current mode (native or filter)
            function getMode() {
                return detectedMode;
            }

            // Force filter mode (useful for sites that claim dark mode but don't implement it well)
            function forceFilterMode() {
                detectedMode = 'filter';
                if (document.documentElement) {
                    document.documentElement.setAttribute(MODE_ATTR, 'filter');
                }
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
                console.log('[WheelDarkMode] init called, isEnabled:', isEnabled);

                // Inject style element IMMEDIATELY - this is critical for preventing flash
                injectStyleImmediate();

                // Apply attribute if enabled - ALWAYS start with filter mode for reliability
                // This ensures dark background immediately, even before detection runs
                if (isEnabled) {
                    console.log('[WheelDarkMode] Calling applyDarkAttribute');
                    applyDarkAttribute();
                } else {
                    console.log('[WheelDarkMode] Dark mode not enabled, skipping');
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

                // Check if site has native dark mode AFTER giving it time to respond to color-scheme
                const detectAndUpdate = function() {
                    // Only switch to native if background is actually dark
                    // This prevents white backgrounds from sites that claim dark mode but don't implement it
                    if (checkIfBackgroundIsDark()) {
                        // Site already has dark background - it might have native dark mode
                        // We can optionally switch to native to reduce filter artifacts
                        // But for now, keep filter mode for consistency
                        // detectedMode = 'native';
                        // document.documentElement.setAttribute(MODE_ATTR, 'native');
                    }
                    // Otherwise keep filter mode (already set)
                };

                // Multiple fallbacks for different loading stages
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', function() {
                        ensureStyle();
                    }, { once: true });
                }

                // Check for native dark mode after full load (all styles applied)
                window.addEventListener('load', function() {
                    ensureStyle();
                    // Give the page a moment to apply styles
                    setTimeout(detectAndUpdate, 100);
                }, { once: true });

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
                getMode: getMode,
                forceFilterMode: forceFilterMode,
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
        let brightnessValue = b / 100.0
        let contrastValue = c / 100.0
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
                document.documentElement.setAttribute('data-wheel-dark-mode', 'filter');

                // Apply inline styles for maximum specificity
                document.documentElement.style.setProperty('background-color', '#1a1a1a', 'important');
                document.documentElement.style.setProperty('min-height', '100%', 'important');

                if (document.body) {
                    const filterValue = 'invert(1) hue-rotate(180deg) brightness(\(brightnessValue)) contrast(\(contrastValue))';
                    document.body.style.setProperty('filter', filterValue, 'important');
                    document.body.style.setProperty('min-height', '100%', 'important');
                }
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
                document.documentElement.removeAttribute('data-wheel-dark-mode');

                // Remove inline styles
                document.documentElement.style.removeProperty('background-color');
                document.documentElement.style.removeProperty('min-height');
                if (document.body) {
                    document.body.style.removeProperty('filter');
                    document.body.style.removeProperty('min-height');
                }
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
