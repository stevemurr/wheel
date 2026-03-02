import Foundation

/// Centralized JavaScript scripts for agent browser interaction.
/// Keeps JS out of AccessibilityBridge so that file focuses on Swift dispatch logic.
enum AgentScripts {

    // MARK: - Snapshot

    static let snapshot = """
    (function() {
        const interactiveSelectors = [
            'a[href]',
            'button',
            'input',
            'select',
            'textarea',
            '[role="button"]',
            '[role="link"]',
            '[role="menuitem"]',
            '[role="tab"]',
            '[role="checkbox"]',
            '[role="radio"]',
            '[role="switch"]',
            '[role="textbox"]',
            '[role="combobox"]',
            '[role="searchbox"]',
            '[onclick]',
            '[tabindex]:not([tabindex="-1"])'
        ];

        const elements = [];
        let id = 0;

        document.querySelectorAll(interactiveSelectors.join(', ')).forEach(el => {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);

            const isVisible = rect.width > 0 &&
                rect.height > 0 &&
                style.visibility !== 'hidden' &&
                style.display !== 'none' &&
                style.opacity !== '0' &&
                rect.top < window.innerHeight &&
                rect.bottom > 0 &&
                rect.left < window.innerWidth &&
                rect.right > 0;

            if (!isVisible) return;

            let text = el.innerText || el.textContent || '';
            text = text.trim().replace(/\\s+/g, ' ');

            const hasInfo = text ||
                el.placeholder ||
                el.getAttribute('aria-label') ||
                el.title ||
                el.alt ||
                (el.tagName === 'A' && el.href);

            if (!hasInfo) return;

            elements.push({
                id: id++,
                tag: el.tagName.toLowerCase(),
                role: el.getAttribute('role') || null,
                text: text || null,
                placeholder: el.placeholder || null,
                ariaLabel: el.getAttribute('aria-label') || el.title || el.alt || null,
                href: el.tagName === 'A' ? el.href : null,
                isVisible: true,
                isEnabled: !el.disabled,
                boundingBox: {
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height
                }
            });

            el.dataset.agentId = String(id - 1);
        });

        let captchaDetected = false;
        let captchaType = null;

        if (document.querySelector('iframe[src*="recaptcha"]') ||
            document.querySelector('.g-recaptcha') ||
            document.querySelector('[data-sitekey]')) {
            captchaDetected = true;
            captchaType = 'reCAPTCHA';
        }

        if (document.querySelector('iframe[src*="hcaptcha"]') ||
            document.querySelector('.h-captcha')) {
            captchaDetected = true;
            captchaType = 'hCaptcha';
        }

        if (document.querySelector('#challenge-running') ||
            document.querySelector('#challenge-form') ||
            document.title.includes('Just a moment') ||
            document.title.includes('Attention Required') ||
            document.body.innerText.includes('Checking your browser') ||
            document.body.innerText.includes('Please wait while we verify')) {
            captchaDetected = true;
            captchaType = 'Cloudflare Challenge';
        }

        const bodyText = document.body.innerText.toLowerCase();
        if (!captchaDetected && (
            bodyText.includes("i'm not a robot") ||
            bodyText.includes("verify you are human") ||
            bodyText.includes("prove you are human") ||
            bodyText.includes("complete the security check") ||
            bodyText.includes("please verify you are a human"))) {
            captchaDetected = true;
            captchaType = 'Human Verification';
        }

        if (document.querySelector('iframe[src*="turnstile"]') ||
            document.querySelector('.cf-turnstile')) {
            captchaDetected = true;
            captchaType = 'Cloudflare Turnstile';
        }

        const headings = [];
        document.querySelectorAll('h1, h2, h3').forEach(h => {
            const hRect = h.getBoundingClientRect();
            const hStyle = window.getComputedStyle(h);
            const hVisible = hRect.width > 0 && hRect.height > 0 &&
                hStyle.visibility !== 'hidden' && hStyle.display !== 'none';
            if (hVisible) {
                const level = parseInt(h.tagName.substring(1));
                const hText = (h.innerText || h.textContent || '').trim().replace(/\\s+/g, ' ');
                if (hText) {
                    headings.push({ level: level, text: hText.substring(0, 200) });
                }
            }
        });

        let contentSummary = null;
        const mainEl = document.querySelector('main, article, [role="main"], .content, #content');
        const contentRoot = mainEl || document.body;
        if (contentRoot) {
            const clone = contentRoot.cloneNode(true);
            clone.querySelectorAll('script, style, nav, footer, header, aside, [aria-hidden="true"]').forEach(el => el.remove());
            let rawText = (clone.textContent || '').replace(/\\s+/g, ' ').trim();
            if (rawText.length > 3000) {
                rawText = rawText.substring(0, 3000) + '...';
            }
            if (rawText.length > 50) {
                contentSummary = rawText;
            }
        }

        return {
            url: window.location.href,
            title: document.title,
            elements: elements,
            scrollPosition: {
                x: window.scrollX,
                y: window.scrollY,
                maxX: document.documentElement.scrollWidth - window.innerWidth,
                maxY: document.documentElement.scrollHeight - window.innerHeight
            },
            viewportSize: {
                width: window.innerWidth,
                height: window.innerHeight
            },
            captchaDetected: captchaDetected,
            captchaType: captchaType,
            headings: headings,
            contentSummary: contentSummary
        };
    })();
    """

    // MARK: - Revalidate Element

    static func revalidateElement(elementId: Int, escapedTag: String, escapedText: String) -> String {
        """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (el) {
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                const isVisible = rect.width > 0 && rect.height > 0 &&
                    style.visibility !== 'hidden' && style.display !== 'none' &&
                    style.opacity !== '0';
                if (isVisible) {
                    return { found: true, id: \(elementId), reMatched: false };
                }
            }

            const tag = "\(escapedTag)";
            const text = "\(escapedText)";
            if (!tag && !text) {
                return { found: false, id: \(elementId), reMatched: false };
            }

            const candidates = tag ? document.querySelectorAll(tag) : document.querySelectorAll('*');
            for (const candidate of candidates) {
                const rect = candidate.getBoundingClientRect();
                const style = window.getComputedStyle(candidate);
                const isVisible = rect.width > 0 && rect.height > 0 &&
                    style.visibility !== 'hidden' && style.display !== 'none';
                if (!isVisible) continue;

                const candidateText = (candidate.innerText || candidate.textContent || '').trim();
                if (text && candidateText.includes(text)) {
                    let newId = candidate.dataset.agentId;
                    if (!newId) {
                        const allIds = document.querySelectorAll('[data-agent-id]');
                        let maxId = 0;
                        allIds.forEach(el => {
                            const id = parseInt(el.dataset.agentId);
                            if (id > maxId) maxId = id;
                        });
                        newId = String(maxId + 1);
                        candidate.dataset.agentId = newId;
                    }
                    return { found: true, id: parseInt(newId), reMatched: true };
                }
            }

            return { found: false, id: \(elementId), reMatched: false };
        })();
        """
    }

    // MARK: - Read Text

    static func readText(elementId: Int) -> String {
        """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found (ID: \(elementId))' };
            }

            let ownText = (el.innerText || el.textContent || '').trim();

            let contextText = '';
            const parent = el.parentElement;
            if (parent) {
                contextText = (parent.innerText || parent.textContent || '').trim();
            }

            let text = contextText.length > ownText.length ? contextText : ownText;
            text = text.replace(/\\s+/g, ' ').trim();

            if (text.length > 2000) {
                text = text.substring(0, 2000) + '...';
            }

            return { success: true, text: text };
        })();
        """
    }

    // MARK: - Click

    static func click(elementId: Int, shiftKey: Bool, metaKey: Bool, ctrlKey: Bool, altKey: Bool, hasModifiers: Bool) -> String {
        let shiftFlag = shiftKey ? "true" : "false"
        let metaFlag = metaKey ? "true" : "false"
        let ctrlFlag = ctrlKey ? "true" : "false"
        let altFlag = altKey ? "true" : "false"
        return """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found (ID: \(elementId)). The page may have changed since the last snapshot.' };
            }

            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            const isVisible = rect.width > 0 &&
                rect.height > 0 &&
                style.visibility !== 'hidden' &&
                style.display !== 'none' &&
                style.opacity !== '0';

            if (!isVisible) {
                return { success: false, error: 'Element exists but is no longer visible (ID: \(elementId))' };
            }

            window.__agentLastElement = el;

            el.scrollIntoView({ behavior: 'instant', block: 'center' });

            if (el.focus) {
                el.focus();
            }

            const x = rect.x + rect.width / 2;
            const y = rect.y + rect.height / 2;

            const clickEvent = new MouseEvent('click', {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: x,
                clientY: y,
                shiftKey: \(shiftFlag),
                metaKey: \(metaFlag),
                ctrlKey: \(ctrlFlag),
                altKey: \(altFlag)
            });

            el.dispatchEvent(clickEvent);

            if (!(\(hasModifiers)) && el.click) {
                el.click();
            }

            return { success: true, elementTag: el.tagName, elementText: (el.innerText || '').substring(0, 50) };
        })();
        """
    }

    // MARK: - Type

    static func type(elementId: Int, escapedText: String) -> String {
        """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found (ID: \(elementId)). The page may have changed since the last snapshot.' };
            }

            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            const isVisible = rect.width > 0 &&
                rect.height > 0 &&
                style.visibility !== 'hidden' &&
                style.display !== 'none';

            if (!isVisible) {
                return { success: false, error: 'Element exists but is no longer visible (ID: \(elementId))' };
            }

            const isTextInput = el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable;
            if (!isTextInput) {
                return { success: false, error: 'Element is not a text input (tag: ' + el.tagName + ')' };
            }

            window.__agentLastElement = el;

            el.focus();

            if (el.value !== undefined) {
                el.value = '';
            } else if (el.isContentEditable) {
                el.textContent = '';
            }

            const text = "\(escapedText)";
            if (el.value !== undefined) {
                el.value = text;
            } else if (el.isContentEditable) {
                el.textContent = text;
            }

            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));

            return { success: true, finalValue: el.value || el.textContent };
        })();
        """
    }

    // MARK: - Press Enter

    static func pressEnter(elementSelector: String) -> String {
        """
        (function() {
            const el = \(elementSelector);
            if (!el || el === document.body) {
                return { success: false, error: 'No element to press enter on' };
            }

            el.focus();

            const keydownEvent = new KeyboardEvent('keydown', {
                bubbles: true,
                cancelable: true,
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13
            });
            el.dispatchEvent(keydownEvent);

            const keypressEvent = new KeyboardEvent('keypress', {
                bubbles: true,
                cancelable: true,
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13
            });
            el.dispatchEvent(keypressEvent);

            const keyupEvent = new KeyboardEvent('keyup', {
                bubbles: true,
                cancelable: true,
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13
            });
            el.dispatchEvent(keyupEvent);

            if (el.form) {
                if (el.form.requestSubmit) {
                    try { el.form.requestSubmit(); } catch(e) {}
                }
                el.form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
            }

            return { success: true };
        })();
        """
    }

    // MARK: - Scroll

    static func scroll(deltaX: Double, deltaY: Double) -> String {
        """
        (function() {
            window.scrollBy({
                left: \(deltaX),
                top: \(deltaY),
                behavior: 'smooth'
            });
            return { success: true };
        })();
        """
    }

    static let scrollToTop = """
    (function() {
        window.scrollTo({ top: 0, behavior: 'smooth' });
        return { success: true };
    })();
    """

    static let scrollToBottom = """
    (function() {
        window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' });
        return { success: true };
    })();
    """

    // MARK: - State Capture

    static let capturePreActionState = """
    (function() {
        const selectors = 'a[href],button,input,select,textarea,[role="button"],[onclick],[tabindex]:not([tabindex="-1"])';
        const count = document.querySelectorAll(selectors).length;
        const hasCaptcha = !!(document.querySelector('iframe[src*="recaptcha"]') ||
            document.querySelector('.g-recaptcha') ||
            document.querySelector('[data-sitekey]') ||
            document.querySelector('iframe[src*="hcaptcha"]') ||
            document.querySelector('.h-captcha') ||
            document.querySelector('#challenge-running') ||
            document.querySelector('#challenge-form') ||
            document.querySelector('iframe[src*="turnstile"]') ||
            document.querySelector('.cf-turnstile'));
        return {
            url: window.location.href,
            title: document.title,
            elementCount: count,
            captchaDetected: hasCaptcha
        };
    })();
    """

    static let interactiveElementCount = """
    (function() {
        const selectors = 'a[href],button,input,select,textarea,[role="button"],[onclick],[tabindex]:not([tabindex="-1"])';
        return document.querySelectorAll(selectors).length;
    })();
    """

    // MARK: - Page Text

    static let pageText = """
    (function() {
        const main = document.querySelector('main, article, [role="main"], .content, #content');
        const body = main || document.body;

        const clone = body.cloneNode(true);
        clone.querySelectorAll('script, style, nav, footer, header, aside').forEach(el => el.remove());

        let text = clone.textContent || '';
        text = text.replace(/\\s+/g, ' ').trim();

        if (text.length > 10000) {
            text = text.substring(0, 10000) + '...';
        }

        return text;
    })();
    """
}
