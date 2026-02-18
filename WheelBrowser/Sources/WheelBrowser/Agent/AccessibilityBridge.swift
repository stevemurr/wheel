import Foundation
import WebKit

/// Represents an interactive element on the page
struct PageElement: Codable, Identifiable {
    let id: Int
    let tag: String
    let role: String?
    let text: String?
    let placeholder: String?
    let ariaLabel: String?
    let href: String?
    let isVisible: Bool
    let isEnabled: Bool
    let boundingBox: BoundingBox?

    struct BoundingBox: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    /// A human-readable description of this element for the LLM
    var description: String {
        var parts: [String] = []

        parts.append("[\(id)]")
        parts.append(tag.uppercased())

        if let role = role, !role.isEmpty {
            parts.append("role=\(role)")
        }

        if let text = text, !text.isEmpty {
            let truncated = text.count > 50 ? String(text.prefix(50)) + "..." : text
            parts.append("\"\(truncated)\"")
        }

        if let placeholder = placeholder, !placeholder.isEmpty {
            parts.append("placeholder=\"\(placeholder)\"")
        }

        if let ariaLabel = ariaLabel, !ariaLabel.isEmpty {
            parts.append("aria-label=\"\(ariaLabel)\"")
        }

        if let href = href, !href.isEmpty {
            let truncatedHref = href.count > 40 ? String(href.prefix(40)) + "..." : href
            parts.append("href=\"\(truncatedHref)\"")
        }

        if !isEnabled {
            parts.append("(disabled)")
        }

        return parts.joined(separator: " ")
    }
}

/// A snapshot of the current page state
struct PageSnapshot: Codable {
    let url: String
    let title: String
    let elements: [PageElement]
    let scrollPosition: ScrollPosition
    let viewportSize: ViewportSize

    struct ScrollPosition: Codable {
        let x: Double
        let y: Double
        let maxX: Double
        let maxY: Double
    }

    struct ViewportSize: Codable {
        let width: Double
        let height: Double
    }

    /// A text representation of the page for the LLM
    var textRepresentation: String {
        var lines: [String] = []
        lines.append("URL: \(url)")
        lines.append("Title: \(title)")
        lines.append("Viewport: \(Int(viewportSize.width))x\(Int(viewportSize.height))")
        lines.append("Scroll: \(Int(scrollPosition.y))/\(Int(scrollPosition.maxY))")
        lines.append("")
        lines.append("Interactive Elements:")

        for element in elements where element.isVisible {
            lines.append("  \(element.description)")
        }

        return lines.joined(separator: "\n")
    }
}

/// Bridge for interacting with web pages through JavaScript injection
@MainActor
class AccessibilityBridge {
    private weak var webView: WKWebView?

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
                }
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

        let script = """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found' };
            }

            // Scroll into view if needed
            el.scrollIntoView({ behavior: 'instant', block: 'center' });

            // Create and dispatch click event
            const rect = el.getBoundingClientRect();
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

            return { success: true };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            if let dict = result as? [String: Any],
               let success = dict["success"] as? Bool,
               !success,
               let error = dict["error"] as? String {
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

        // Escape the text for JavaScript
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let script = """
        (function() {
            const el = document.querySelector('[data-agent-id="\(elementId)"]');
            if (!el) {
                return { success: false, error: 'Element not found' };
            }

            // Focus the element
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

            return { success: true };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            if let dict = result as? [String: Any],
               let success = dict["success"] as? Bool,
               !success,
               let error = dict["error"] as? String {
                throw AgentError.typeFailed(error)
            }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.typeFailed(error.localizedDescription)
        }
    }

    // MARK: - Press Enter

    /// Press enter on the currently focused element
    func pressEnter() async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let script = """
        (function() {
            const el = document.activeElement;
            if (!el) {
                return { success: false, error: 'No element focused' };
            }

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
                el.form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
            }

            return { success: true };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            if let dict = result as? [String: Any],
               let success = dict["success"] as? Bool,
               !success,
               let error = dict["error"] as? String {
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

    /// Wait for the page to finish loading or for a specified duration
    func waitForLoad(timeout: TimeInterval = 5.0) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if !webView.isLoading {
                // Additional wait for dynamic content
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
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
