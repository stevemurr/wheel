(function() {
    if (window.__wheelCookieBannerCleanerInstalled) return;
    window.__wheelCookieBannerCleanerInstalled = true;

    const HIDE_SELECTORS = [
        '[id*="cookie-banner"]',
        '[class*="cookie-banner"]',
        '[id*="cookie-consent"]',
        '[class*="cookie-consent"]',
        '[aria-label*="cookie" i]',
        '[data-testid*="cookie" i]',
        '[data-cookiebanner]',
        '.cc-window',
        '.qc-cmp2-container',
        '#onetrust-consent-sdk'
    ];

    const BUTTON_PATTERNS = [
        /accept/i,
        /agree/i,
        /allow all/i,
        /continue/i,
        /got it/i,
        /ok/i
    ];

    function shouldAllowlistHost() {
        if (!window.__wheelAllowlistedHosts || !Array.isArray(window.__wheelAllowlistedHosts)) {
            return false;
        }
        const host = location.hostname.toLowerCase();
        return window.__wheelAllowlistedHosts.some(function(entry) {
            const suffix = String(entry || '').toLowerCase();
            return suffix && (host === suffix || host.endsWith('.' + suffix));
        });
    }

    function hideKnownBanners() {
        HIDE_SELECTORS.forEach(function(selector) {
            document.querySelectorAll(selector).forEach(function(node) {
                node.style.setProperty('display', 'none', 'important');
                node.style.setProperty('visibility', 'hidden', 'important');
            });
        });
    }

    function clickConsentButtons() {
        document.querySelectorAll('button, [role="button"], a').forEach(function(element) {
            const text = (element.textContent || '').trim();
            if (!text) return;
            if (!BUTTON_PATTERNS.some(function(pattern) { return pattern.test(text); })) return;

            const rect = element.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) return;

            element.click();
        });
    }

    if (shouldAllowlistHost()) return;

    hideKnownBanners();
    clickConsentButtons();

    const observer = new MutationObserver(function() {
        hideKnownBanners();
        clickConsentButtons();
    });

    observer.observe(document.documentElement || document.body, {
        childList: true,
        subtree: true
    });
})();
