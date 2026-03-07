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

    const BANNER_ROOT_SELECTORS = [
        ...HIDE_SELECTORS,
        '[id*="cookie"]',
        '[class*="cookie"]',
        '[id*="consent"]',
        '[class*="consent"]',
        '[id*="privacy"]',
        '[class*="privacy"]',
        '.didomi-popup-container',
        '.fc-consent-root',
        '.ot-sdk-container'
    ];

    const REJECT_BUTTON_PATTERNS = [
        /\breject all\b/i,
        /\breject\b/i,
        /\bdecline\b/i,
        /\bdeny\b/i,
        /\brefuse\b/i,
        /\bdisallow\b/i,
        /\bnecessary cookies only\b/i,
        /\bonly necessary cookies\b/i,
        /\bstrictly necessary\b/i,
        /\bessential cookies only\b/i,
        /\bonly essential cookies\b/i,
        /\bnecessary only\b/i,
        /\bessential only\b/i,
        /\buse only necessary\b/i,
        /\buse only essential\b/i,
        /\bcontinue without accepting\b/i,
        /\bdo not consent\b/i,
        /\bdo not accept\b/i,
        /\bopt out\b/i
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

    function suppressNode(node) {
        node.style.setProperty('display', 'none', 'important');
        node.style.setProperty('visibility', 'hidden', 'important');
        node.style.setProperty('pointer-events', 'none', 'important');
    }

    function hideKnownBanners(containers) {
        HIDE_SELECTORS.forEach(function(selector) {
            document.querySelectorAll(selector).forEach(function(node) {
                suppressNode(node);
            });
        });

        (containers || []).forEach(function(container) {
            if (bannerLooksLikeConsentUI(container)) {
                suppressNode(container);
            }
        });
    }

    function findBannerContainers() {
        const seen = new Set();
        const containers = [];

        BANNER_ROOT_SELECTORS.forEach(function(selector) {
            document.querySelectorAll(selector).forEach(function(node) {
                if (seen.has(node)) return;
                seen.add(node);
                containers.push(node);
            });
        });

        return containers;
    }

    function bannerLooksLikeConsentUI(container) {
        const text = (container.textContent || '').toLowerCase();
        return text.includes('cookie') || text.includes('consent') || text.includes('privacy');
    }

    function buttonText(element) {
        return (
            element.textContent ||
            element.value ||
            element.getAttribute('aria-label') ||
            ''
        ).trim();
    }

    function isVisible(element) {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
    }

    function isClickableButton(element) {
        if (element.dataset.wheelConsentClicked === '1') return false;
        if (element.disabled) return false;
        return isVisible(element);
    }

    function rejectionScore(text) {
        for (let index = 0; index < REJECT_BUTTON_PATTERNS.length; index += 1) {
            if (REJECT_BUTTON_PATTERNS[index].test(text)) {
                return REJECT_BUTTON_PATTERNS.length - index;
            }
        }
        return 0;
    }

    function clickRejectButtons(containers) {
        let clicked = false;

        containers.forEach(function(container) {
            if (!bannerLooksLikeConsentUI(container)) return;

            let bestButton = null;
            let bestScore = 0;

            container.querySelectorAll('button, [role="button"], input[type="button"], input[type="submit"]').forEach(function(element) {
                if (!isClickableButton(element)) return;

                const text = buttonText(element);
                if (!text) return;

                const score = rejectionScore(text);
                if (score <= bestScore) return;

                bestButton = element;
                bestScore = score;
            });

            if (!bestButton) return;

            bestButton.dataset.wheelConsentClicked = '1';
            bestButton.click();
            clicked = true;
        });

        return clicked;
    }

    function restoreScrollingIfNeeded(containers) {
        if (!containers.length) return;
        document.documentElement.style.removeProperty('overflow');
        document.body.style.removeProperty('overflow');
    }

    if (shouldAllowlistHost()) return;

    function processBanners() {
        const containers = findBannerContainers().filter(bannerLooksLikeConsentUI);
        clickRejectButtons(containers);
        hideKnownBanners(containers);
        restoreScrollingIfNeeded(containers);
    }

    processBanners();

    const observer = new MutationObserver(function() {
        processBanners();
    });

    observer.observe(document.documentElement || document.body, {
        childList: true,
        subtree: true
    });
})();
