import Foundation
import WebKit

/// JavaScript-based cookie banner auto-dismissal system.
/// Works in three layers:
/// 1. CSS display:none rules (existing, in BlockingRules.swift) hide known banner selectors instantly
/// 2. CMP-specific handlers call platform APIs (Cookiebot.decline(), OneTrust reject, etc.)
/// 3. Generic banner detection via MutationObserver + button text matching
enum CookieBannerScripts {

    /// Creates a WKUserScript for cookie banner dismissal, injected at document end.
    static func createUserScript() -> WKUserScript {
        WKUserScript(
            source: dismissalScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    // MARK: - JavaScript

    private static let dismissalScript = """
    (function() {
        'use strict';

        // Avoid double-injection
        if (window.__wheelCookieBanner) return;

        var MAX_ATTEMPTS = 5;
        var OBSERVER_TIMEOUT = 15000;
        var attemptCount = 0;

        // =============================================
        // CMP-Specific Handlers
        // =============================================

        var cmpHandlers = [
            // OneTrust / CookieLaw
            {
                name: 'OneTrust',
                detect: function() {
                    return typeof OneTrust !== 'undefined' || typeof OptanonWrapper !== 'undefined'
                        || document.getElementById('onetrust-banner-sdk');
                },
                dismiss: function() {
                    // Try the reject-all button first
                    var rejectBtn = document.getElementById('onetrust-reject-all-handler')
                        || document.querySelector('.ot-pc-refuse-all-handler');
                    if (rejectBtn) { rejectBtn.click(); return true; }

                    // Fall back to API
                    if (typeof OneTrust !== 'undefined' && OneTrust.RejectAll) {
                        OneTrust.RejectAll();
                        return true;
                    }

                    // Close the banner
                    var closeBtn = document.getElementById('onetrust-close-btn-container');
                    if (closeBtn) { closeBtn.click(); return true; }

                    var banner = document.getElementById('onetrust-banner-sdk');
                    if (banner) { banner.style.display = 'none'; return true; }
                    return false;
                }
            },
            // Cookiebot
            {
                name: 'Cookiebot',
                detect: function() {
                    return typeof Cookiebot !== 'undefined' || document.getElementById('CybotCookiebotDialog');
                },
                dismiss: function() {
                    if (typeof Cookiebot !== 'undefined' && Cookiebot.decline) {
                        Cookiebot.decline();
                        return true;
                    }
                    var declineBtn = document.getElementById('CybotCookiebotDialogBodyButtonDecline')
                        || document.querySelector('.CybotCookiebotDialogBodyButton[id*="Decline"]');
                    if (declineBtn) { declineBtn.click(); return true; }
                    var dialog = document.getElementById('CybotCookiebotDialog');
                    if (dialog) { dialog.style.display = 'none'; return true; }
                    return false;
                }
            },
            // TrustArc
            {
                name: 'TrustArc',
                detect: function() {
                    return typeof truste !== 'undefined' || document.getElementById('truste-consent-track')
                        || document.querySelector('.truste_overlay');
                },
                dismiss: function() {
                    var closeBtn = document.querySelector('.truste_popframe .close')
                        || document.getElementById('truste-consent-close');
                    if (closeBtn) { closeBtn.click(); return true; }
                    var overlay = document.querySelector('.truste_overlay');
                    if (overlay) { overlay.style.display = 'none'; return true; }
                    var track = document.getElementById('truste-consent-track');
                    if (track) { track.style.display = 'none'; return true; }
                    return false;
                }
            },
            // Quantcast Choice
            {
                name: 'Quantcast',
                detect: function() {
                    return typeof __tcfapi !== 'undefined' || document.querySelector('.qc-cmp2-container')
                        || document.getElementById('qcCmpUi');
                },
                dismiss: function() {
                    // Try Quantcast CMP v2 reject button
                    var rejectBtn = document.querySelector('.qc-cmp2-summary-buttons button[mode="secondary"]')
                        || document.querySelector('.qc-cmp2-footer button:last-child');
                    if (rejectBtn) { rejectBtn.click(); return true; }
                    var container = document.querySelector('.qc-cmp2-container');
                    if (container) { container.style.display = 'none'; return true; }
                    return false;
                }
            },
            // Didomi
            {
                name: 'Didomi',
                detect: function() {
                    return typeof Didomi !== 'undefined' || document.getElementById('didomi-popup');
                },
                dismiss: function() {
                    if (typeof Didomi !== 'undefined') {
                        try {
                            Didomi.setUserDisagreeToAll();
                            return true;
                        } catch(e) {}
                    }
                    var disagreeBtn = document.getElementById('didomi-notice-disagree-button')
                        || document.querySelector('[data-testid="notice-disagree-button"]');
                    if (disagreeBtn) { disagreeBtn.click(); return true; }
                    var popup = document.getElementById('didomi-popup');
                    if (popup) { popup.style.display = 'none'; return true; }
                    return false;
                }
            },
            // Usercentrics (often uses Shadow DOM)
            {
                name: 'Usercentrics',
                detect: function() {
                    return typeof UC_UI !== 'undefined' || document.getElementById('usercentrics-root');
                },
                dismiss: function() {
                    if (typeof UC_UI !== 'undefined' && UC_UI.denyAllConsents) {
                        UC_UI.denyAllConsents();
                        return true;
                    }
                    // Shadow DOM approach
                    var root = document.getElementById('usercentrics-root');
                    if (root && root.shadowRoot) {
                        var denyBtn = root.shadowRoot.querySelector('[data-testid="uc-deny-all-button"]')
                            || root.shadowRoot.querySelector('button[class*="deny"]');
                        if (denyBtn) { denyBtn.click(); return true; }
                    }
                    return false;
                }
            },
            // Klaro
            {
                name: 'Klaro',
                detect: function() {
                    return typeof klaro !== 'undefined' || document.querySelector('.klaro .cookie-notice');
                },
                dismiss: function() {
                    if (typeof klaro !== 'undefined' && klaro.getManager) {
                        try {
                            var mgr = klaro.getManager();
                            mgr.changeAll(false);
                            mgr.saveAndApplyConsents();
                            return true;
                        } catch(e) {}
                    }
                    var declineBtn = document.querySelector('.klaro .cn-decline')
                        || document.querySelector('.klaro button[class*="decline"]');
                    if (declineBtn) { declineBtn.click(); return true; }
                    return false;
                }
            },
            // Sourcepoint
            {
                name: 'Sourcepoint',
                detect: function() {
                    return typeof _sp_ !== 'undefined' || document.querySelector('[id^="sp_message_container"]');
                },
                dismiss: function() {
                    // Sourcepoint uses iframes; try to find reject button in container
                    var containers = document.querySelectorAll('[id^="sp_message_container"]');
                    for (var i = 0; i < containers.length; i++) {
                        var iframe = containers[i].querySelector('iframe');
                        if (iframe) {
                            try {
                                var iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                                var rejectBtn = iframeDoc.querySelector('button[title*="Reject"]')
                                    || iframeDoc.querySelector('button[title*="reject"]');
                                if (rejectBtn) { rejectBtn.click(); return true; }
                            } catch(e) { /* cross-origin */ }
                        }
                        containers[i].style.display = 'none';
                    }
                    return containers.length > 0;
                }
            }
        ];

        // =============================================
        // Generic Banner Detection
        // =============================================

        var bannerSelectors = [
            '#cookie-banner', '#cookie-consent', '#cookie-notice', '#cookie-popup',
            '#cookie-modal', '#cookie-law-info-bar', '#cookie-policy',
            '#cookiebanner', '#js-cookie-banner', '#gdpr-banner', '#gdpr-consent',
            '#consent-banner', '#consent-popup', '#privacy-banner',
            '.cookie-banner', '.cookie-consent', '.cookie-notice', '.cookie-popup',
            '.cookie-modal', '.cookie-bar', '.cookie-alert', '.cookie-warning',
            '.gdpr-banner', '.gdpr-consent', '.consent-banner', '.consent-popup',
            '.privacy-banner', '.cc-banner', '.cc-window',
            '[class*="CookieConsent"]', '[class*="cookieConsent"]',
            '[class*="cookie-consent"]', '[class*="cookie_consent"]',
            '[class*="cookie-banner"]', '[class*="cookie_banner"]',
            '[id*="cookie-consent"]', '[id*="cookie_consent"]',
            '[role="dialog"][class*="consent" i]',
            '[role="dialog"][class*="cookie" i]',
            '[role="dialog"][class*="gdpr" i]',
            '[aria-label*="cookie" i]', '[aria-label*="consent" i]'
        ];

        // Button text patterns for "reject" / "decline" / "necessary only" in EN, DE, FR, ES, IT
        var rejectPatterns = [
            /^reject\\s*(all)?$/i,
            /^deny\\s*(all)?$/i,
            /^decline\\s*(all)?$/i,
            /^refuse\\s*(all)?$/i,
            /^necessary\\s*only$/i,
            /^only\\s*necessary$/i,
            /^essential\\s*only$/i,
            /^only\\s*essential/i,
            /^no,?\\s*thanks?$/i,
            /^do\\s*not\\s*(accept|consent)/i,
            // German
            /^alle\\s*ablehnen$/i,
            /^ablehnen$/i,
            /^nur\\s*notwendige$/i,
            /^nur\\s*essenzielle$/i,
            // French
            /^tout\\s*refuser$/i,
            /^refuser$/i,
            /^continuer\\s*sans\\s*accepter$/i,
            // Spanish
            /^rechazar\\s*(todo)?$/i,
            /^solo\\s*necesarias$/i,
            // Italian
            /^rifiuta\\s*(tutto|tutti)?$/i,
            /^solo\\s*necessari$/i
        ];

        // Secondary: "accept" / "agree" / "OK" (less preferred, last resort)
        var acceptPatterns = [
            /^accept\\s*(all)?$/i,
            /^agree$/i,
            /^I\\s*agree$/i,
            /^got\\s*it$/i,
            /^ok$/i
        ];

        // Protected elements — never remove these
        var protectedSelectors = ['main', 'article', '#app', '#root', '#__next', '#content', '.main-content'];

        function isProtectedElement(el) {
            for (var i = 0; i < protectedSelectors.length; i++) {
                if (el.matches && el.matches(protectedSelectors[i])) return true;
            }
            return false;
        }

        function coversViewport(el) {
            var rect = el.getBoundingClientRect();
            var vw = window.innerWidth;
            var vh = window.innerHeight;
            return (rect.width * rect.height) > (vw * vh * 0.8);
        }

        function findButtonByText(container, patterns) {
            var buttons = container.querySelectorAll('button, a[role="button"], [role="button"], input[type="button"], input[type="submit"]');
            for (var i = 0; i < buttons.length; i++) {
                var text = (buttons[i].textContent || buttons[i].value || '').trim();
                for (var j = 0; j < patterns.length; j++) {
                    if (patterns[j].test(text)) return buttons[i];
                }
            }
            return null;
        }

        function removeOverlays() {
            // Remove backdrop/overlay elements commonly added by consent dialogs
            var overlays = document.querySelectorAll(
                '.modal-backdrop, .overlay, .consent-overlay, ' +
                '[class*="cookie-overlay"], [class*="consent-overlay"], ' +
                '[class*="CookieConsent__Overlay"], [class*="gdpr-overlay"]'
            );
            overlays.forEach(function(el) {
                if (!isProtectedElement(el)) {
                    el.style.display = 'none';
                }
            });

            // Restore body scroll
            if (document.body.style.overflow === 'hidden' || document.body.style.overflow === 'clip') {
                document.body.style.overflow = '';
            }
            if (document.documentElement.style.overflow === 'hidden' || document.documentElement.style.overflow === 'clip') {
                document.documentElement.style.overflow = '';
            }
            document.body.classList.remove('no-scroll', 'modal-open', 'cookie-open');
        }

        function dismissGenericBanner(el) {
            if (!el || isProtectedElement(el) || coversViewport(el)) return false;

            // Try reject button first
            var btn = findButtonByText(el, rejectPatterns);
            if (btn) {
                btn.click();
                removeOverlays();
                return true;
            }

            // Try accept button as last resort (better than leaving banner)
            btn = findButtonByText(el, acceptPatterns);
            if (btn) {
                btn.click();
                removeOverlays();
                return true;
            }

            // Last resort: hide the element
            el.style.display = 'none';
            removeOverlays();
            return true;
        }

        // =============================================
        // Main Dismiss Logic
        // =============================================

        function dismiss() {
            attemptCount++;
            if (attemptCount > MAX_ATTEMPTS) return false;

            // Layer 2: Try CMP-specific handlers
            for (var i = 0; i < cmpHandlers.length; i++) {
                try {
                    if (cmpHandlers[i].detect()) {
                        if (cmpHandlers[i].dismiss()) {
                            removeOverlays();
                            return true;
                        }
                    }
                } catch(e) { /* ignore handler errors */ }
            }

            // Layer 3: Generic banner detection
            for (var j = 0; j < bannerSelectors.length; j++) {
                try {
                    var banners = document.querySelectorAll(bannerSelectors[j]);
                    for (var k = 0; k < banners.length; k++) {
                        var banner = banners[k];
                        // Only target visible banners
                        var style = window.getComputedStyle(banner);
                        if (style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0') {
                            if (dismissGenericBanner(banner)) return true;
                        }
                    }
                } catch(e) { /* ignore selector errors */ }
            }

            return false;
        }

        // =============================================
        // MutationObserver for Dynamic Banners
        // =============================================

        var observer = null;
        var observerTimer = null;
        var debounceTimer = null;

        function startObserver() {
            if (!document.body) return;

            observer = new MutationObserver(function(mutations) {
                // Debounce to avoid excessive processing
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(function() {
                    dismiss();
                }, 200);
            });

            observer.observe(document.body, {
                childList: true,
                subtree: true
            });

            // Auto-disconnect after timeout
            observerTimer = setTimeout(function() {
                if (observer) {
                    observer.disconnect();
                    observer = null;
                }
            }, OBSERVER_TIMEOUT);
        }

        function stopObserver() {
            clearTimeout(observerTimer);
            clearTimeout(debounceTimer);
            if (observer) {
                observer.disconnect();
                observer = null;
            }
        }

        // =============================================
        // Public API
        // =============================================

        window.__wheelCookieBanner = {
            dismiss: function() {
                attemptCount = 0;
                return dismiss();
            },
            stop: function() {
                stopObserver();
            }
        };

        // Initial attempt
        dismiss();

        // Start watching for dynamically injected banners
        startObserver();
    })();
    """
}
