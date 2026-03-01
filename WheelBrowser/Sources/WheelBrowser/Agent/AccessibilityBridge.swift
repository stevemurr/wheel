import Foundation
import WebKit

/// Bridge for interacting with web pages through JavaScript injection
@MainActor
class AccessibilityBridge {
    private weak var webView: WKWebView?

    /// Track the last element we interacted with for pressEnter
    private var lastInteractedElementId: Int?

    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Snapshot

    /// Capture a snapshot of interactive elements on the current page
    func snapshot() async throws -> PageSnapshot {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let script = """
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

                // Check visibility
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

                // Get text content
                let text = el.innerText || el.textContent || '';
                text = text.trim().replace(/\\s+/g, ' ');

                // Skip elements with no useful identifying info
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

                // Store reference for later clicks
                el.dataset.agentId = String(id - 1);
            });

            // Detect captcha/challenge pages
            let captchaDetected = false;
            let captchaType = null;

            // Check for reCAPTCHA
            if (document.querySelector('iframe[src*="recaptcha"]') ||
                document.querySelector('.g-recaptcha') ||
                document.querySelector('[data-sitekey]')) {
                captchaDetected = true;
                captchaType = 'reCAPTCHA';
            }

            // Check for hCaptcha
            if (document.querySelector('iframe[src*="hcaptcha"]') ||
                document.querySelector('.h-captcha')) {
                captchaDetected = true;
                captchaType = 'hCaptcha';
            }

            // Check for Cloudflare challenge
            if (document.querySelector('#challenge-running') ||
                document.querySelector('#challenge-form') ||
                document.title.includes('Just a moment') ||
                document.title.includes('Attention Required') ||
                document.body.innerText.includes('Checking your browser') ||
                document.body.innerText.includes('Please wait while we verify')) {
                captchaDetected = true;
                captchaType = 'Cloudflare Challenge';
            }

            // Check for common captcha text patterns
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

            // Check for Turnstile (Cloudflare's newer captcha)
            if (document.querySelector('iframe[src*="turnstile"]') ||
                document.querySelector('.cf-turnstile')) {
                captchaDetected = true;
                captchaType = 'Cloudflare Turnstile';
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
                captchaType: captchaType
            };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            guard let dict = result as? [String: Any] else {
                throw AgentError.snapshotFailed("Invalid response format")
            }

            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            let snapshot = try JSONDecoder().decode(PageSnapshot.self, from: jsonData)
            return snapshot
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.snapshotFailed(error.localizedDescription)
        }
    }

    // MARK: - Click

    /// Click an element by its agent ID
    func click(elementId: Int) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        // Track for pressEnter
        lastInteractedElementId = elementId

        let script = """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found (ID: \(elementId)). The page may have changed since the last snapshot.' };
            }

            // Verify element is still visible and interactable
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

            // Store as last interacted element globally
            window.__agentLastElement = el;

            // Scroll into view if needed
            el.scrollIntoView({ behavior: 'instant', block: 'center' });

            // Focus the element first (helps with background tabs)
            if (el.focus) {
                el.focus();
            }

            // Create and dispatch click event
            const x = rect.x + rect.width / 2;
            const y = rect.y + rect.height / 2;

            const clickEvent = new MouseEvent('click', {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: x,
                clientY: y
            });

            el.dispatchEvent(clickEvent);

            // Also try direct click for links and buttons
            if (el.click) {
                el.click();
            }

            return { success: true, elementTag: el.tagName, elementText: (el.innerText || '').substring(0, 50) };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            // Handle nil result - JavaScript may have crashed or timed out
            guard let dict = result as? [String: Any] else {
                throw AgentError.clickFailed("JavaScript execution returned no result (element ID: \(elementId)). The page may be unresponsive.")
            }

            // Check for explicit failure
            guard let success = dict["success"] as? Bool else {
                throw AgentError.clickFailed("Invalid response from click script (missing success field)")
            }

            if !success {
                let error = dict["error"] as? String ?? "Unknown click error"
                throw AgentError.clickFailed(error)
            }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.clickFailed(error.localizedDescription)
        }
    }

    // MARK: - Type

    /// Type text into an element by its agent ID
    func type(elementId: Int, text: String) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        // Track for pressEnter
        lastInteractedElementId = elementId

        // Escape the text for JavaScript using secure escaper
        let escapedText = JavaScriptEscaper.escape(text)

        let script = """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found (ID: \(elementId)). The page may have changed since the last snapshot.' };
            }

            // Verify element is still visible
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            const isVisible = rect.width > 0 &&
                rect.height > 0 &&
                style.visibility !== 'hidden' &&
                style.display !== 'none';

            if (!isVisible) {
                return { success: false, error: 'Element exists but is no longer visible (ID: \(elementId))' };
            }

            // Verify element is a text input type
            const isTextInput = el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable;
            if (!isTextInput) {
                return { success: false, error: 'Element is not a text input (tag: ' + el.tagName + ')' };
            }

            // Store as last interacted element globally
            window.__agentLastElement = el;

            // Focus the element explicitly
            el.focus();

            // Clear existing content
            if (el.value !== undefined) {
                el.value = '';
            } else if (el.isContentEditable) {
                el.textContent = '';
            }

            // Set the new value
            const text = "\(escapedText)";
            if (el.value !== undefined) {
                el.value = text;
            } else if (el.isContentEditable) {
                el.textContent = text;
            }

            // Trigger input event
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));

            return { success: true, finalValue: el.value || el.textContent };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            // Handle nil result - JavaScript may have crashed or timed out
            guard let dict = result as? [String: Any] else {
                throw AgentError.typeFailed("JavaScript execution returned no result (element ID: \(elementId)). The page may be unresponsive.")
            }

            // Check for explicit failure
            guard let success = dict["success"] as? Bool else {
                throw AgentError.typeFailed("Invalid response from type script (missing success field)")
            }

            if !success {
                let error = dict["error"] as? String ?? "Unknown type error"
                throw AgentError.typeFailed(error)
            }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.typeFailed(error.localizedDescription)
        }
    }

    // MARK: - Press Enter

    /// Press enter on the last interacted element (or focused element as fallback)
    func pressEnter() async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        // Build selector for last interacted element if available
        let elementSelector: String
        if let lastId = lastInteractedElementId {
            elementSelector = """
            window.__agentLastElement ||
            document.querySelector('[data-agent-id="\(lastId)"]') ||
            document.activeElement
            """
        } else {
            elementSelector = "window.__agentLastElement || document.activeElement"
        }

        let script = """
        (function() {
            // Try to get the last interacted element, fall back to activeElement
            const el = \(elementSelector);
            if (!el || el === document.body) {
                return { success: false, error: 'No element to press enter on' };
            }

            // Re-focus the element in case focus was lost
            el.focus();

            // Dispatch keydown event
            const keydownEvent = new KeyboardEvent('keydown', {
                bubbles: true,
                cancelable: true,
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13
            });
            el.dispatchEvent(keydownEvent);

            // Dispatch keypress event
            const keypressEvent = new KeyboardEvent('keypress', {
                bubbles: true,
                cancelable: true,
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13
            });
            el.dispatchEvent(keypressEvent);

            // Dispatch keyup event
            const keyupEvent = new KeyboardEvent('keyup', {
                bubbles: true,
                cancelable: true,
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13
            });
            el.dispatchEvent(keyupEvent);

            // If it's a form element, try submitting the form
            if (el.form) {
                // Try both requestSubmit (modern) and submit event
                if (el.form.requestSubmit) {
                    try { el.form.requestSubmit(); } catch(e) {}
                }
                el.form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
            }

            return { success: true };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            // Handle nil result
            guard let dict = result as? [String: Any] else {
                throw AgentError.typeFailed("JavaScript execution returned no result for pressEnter. The page may be unresponsive.")
            }

            guard let success = dict["success"] as? Bool else {
                throw AgentError.typeFailed("Invalid response from pressEnter script (missing success field)")
            }

            if !success {
                let error = dict["error"] as? String ?? "Unknown pressEnter error"
                throw AgentError.typeFailed(error)
            }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.typeFailed(error.localizedDescription)
        }
    }

    // MARK: - Scroll

    /// Scroll the page by a delta
    func scroll(deltaX: Double = 0, deltaY: Double) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let script = """
        (function() {
            window.scrollBy({
                left: \(deltaX),
                top: \(deltaY),
                behavior: 'smooth'
            });
            return { success: true };
        })();
        """

        do {
            _ = try await webView.evaluateJavaScript(script)
        } catch {
            throw AgentError.scrollFailed(error.localizedDescription)
        }
    }

    /// Scroll to top of page
    func scrollToTop() async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let script = """
        (function() {
            window.scrollTo({ top: 0, behavior: 'smooth' });
            return { success: true };
        })();
        """

        do {
            _ = try await webView.evaluateJavaScript(script)
        } catch {
            throw AgentError.scrollFailed(error.localizedDescription)
        }
    }

    /// Scroll to bottom of page
    func scrollToBottom() async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let script = """
        (function() {
            window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' });
            return { success: true };
        })();
        """

        do {
            _ = try await webView.evaluateJavaScript(script)
        } catch {
            throw AgentError.scrollFailed(error.localizedDescription)
        }
    }

    // MARK: - Wait

    /// Wait for the page to finish loading with DOM stability detection for SPAs
    /// - Parameters:
    ///   - timeout: Maximum time to wait for load
    ///   - stableThreshold: Time the DOM must be stable before considering it loaded
    func waitForLoad(timeout: TimeInterval = 5.0, stableThreshold: TimeInterval = 0.5) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let startTime = Date()
        var lastElementCount = -1
        var lastChangeTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            // First wait for basic loading to complete
            if webView.isLoading {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                continue
            }

            // Then check for DOM stability (especially important for SPAs)
            let currentCount = await getInteractiveElementCount()

            if currentCount != lastElementCount {
                // DOM changed, reset stability timer
                lastElementCount = currentCount
                lastChangeTime = Date()
            } else if Date().timeIntervalSince(lastChangeTime) >= stableThreshold {
                // DOM has been stable for threshold duration
                return
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }

    /// Get the count of interactive elements on the page
    private func getInteractiveElementCount() async -> Int {
        guard let webView = webView else { return -1 }

        let script = """
        (function() {
            const selectors = 'a[href],button,input,select,textarea,[role="button"],[onclick],[tabindex]:not([tabindex="-1"])';
            return document.querySelectorAll(selectors).length;
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)
            return (result as? Int) ?? -1
        } catch {
            return -1
        }
    }

    // MARK: - Get Page Text

    /// Get the main text content of the page
    func getPageText() async throws -> String {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let script = """
        (function() {
            // Get main content areas
            const main = document.querySelector('main, article, [role="main"], .content, #content');
            const body = main || document.body;

            // Remove script and style content
            const clone = body.cloneNode(true);
            clone.querySelectorAll('script, style, nav, footer, header, aside').forEach(el => el.remove());

            let text = clone.textContent || '';
            // Clean up whitespace
            text = text.replace(/\\s+/g, ' ').trim();

            // Limit length
            if (text.length > 10000) {
                text = text.substring(0, 10000) + '...';
            }

            return text;
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)
            return (result as? String) ?? ""
        } catch {
            throw AgentError.javascriptError(error.localizedDescription)
        }
    }
}
