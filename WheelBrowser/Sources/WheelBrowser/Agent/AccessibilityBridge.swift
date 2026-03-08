import Foundation
import WebKit

/// Bridge for interacting with web pages through JavaScript injection
@MainActor
class AccessibilityBridge: BrowserBridge {
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

        do {
            let result = try await webView.evaluateJavaScript(AgentScripts.snapshot)

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

    func snapshot(request: SnapshotRequest) async throws -> ReducedPageObservation {
        let pageSnapshot = try await snapshot()
        let linkRequest = LinkCollectionRequest(
            allowedHosts: request.relevantHosts,
            includePaginationLinks: request.includePaginationControls,
            maxMatches: max(request.maxRelevantLinks * 3, request.maxRelevantLinks)
        )
        let linkResult = try await collectLinks(linkRequest)
        return ReducedPageObservation(
            snapshot: pageSnapshot,
            request: request,
            relevantLinks: linkResult.matches.map {
                PageLink(text: $0.text, url: $0.url, isPaginationControl: false)
            },
            paginationLinks: request.includePaginationControls ? linkResult.paginationLinks : [],
            totalPageLinkCount: linkResult.totalLinksScanned
        )
    }

    // MARK: - Element Re-validation

    /// Validate that an element still exists and is visible. If not, attempt to re-find by text/tag match.
    /// Returns the (possibly updated) element ID to use.
    func revalidateElement(elementId: Int, expectedTag: String?, expectedText: String?) async throws -> Int {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let escapedTag = JavaScriptEscaper.escape(expectedTag ?? "")
        let escapedText = JavaScriptEscaper.escape(expectedText ?? "")

        let script = AgentScripts.revalidateElement(
            elementId: elementId,
            escapedTag: escapedTag,
            escapedText: escapedText
        )

        do {
            let result = try await webView.evaluateJavaScript(script)
            guard let dict = result as? [String: Any],
                  let found = dict["found"] as? Bool else {
                Log.Agent.warning("revalidateElement(#\(elementId)): Unexpected JS result format, returning original ID")
                return elementId
            }

            if found {
                let resolvedId = dict["id"] as? Int ?? elementId
                let reMatched = dict["reMatched"] as? Bool ?? false
                if reMatched {
                    Log.Agent.info("Element #\(elementId) re-matched to #\(resolvedId) by text/tag")
                }
                return resolvedId
            }

            return elementId
        } catch {
            Log.Agent.warning("revalidateElement(#\(elementId)): JS error: \(error.localizedDescription), returning original ID")
            return elementId
        }
    }

    // MARK: - Read Text

    /// Read the text content in the vicinity of an element
    func readText(elementId: Int) async throws -> String {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        do {
            let result = try await webView.evaluateJavaScript(AgentScripts.readText(elementId: elementId))
            guard let dict = result as? [String: Any],
                  let success = dict["success"] as? Bool else {
                throw AgentError.javascriptError("Invalid response from readText script")
            }

            if !success {
                let error = dict["error"] as? String ?? "Unknown readText error"
                throw AgentError.javascriptError(error)
            }

            return dict["text"] as? String ?? ""
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.javascriptError(error.localizedDescription)
        }
    }

    // MARK: - Read Links

    /// Get all links on the page (deduplicated, capped at 50)
    func getPageLinks() async throws -> String {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        do {
            let result = try await webView.evaluateJavaScript(AgentScripts.readLinks)
            if result == nil || result is NSNull {
                return ""
            }
            guard let links = result as? String else {
                throw AgentError.javascriptError("getPageLinks: Expected String but got \(Swift.type(of: result))")
            }
            return links
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.javascriptError(error.localizedDescription)
        }
    }

    func collectLinks(_ request: LinkCollectionRequest) async throws -> LinkCollectionResult {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        do {
            let jsonData = try JSONEncoder().encode(request.allowedHosts)
            let allowedHostsJSON = String(data: jsonData, encoding: .utf8) ?? "[]"
            let script = AgentScripts.collectLinks(
                allowedHostsJSON: allowedHostsJSON,
                maxMatches: request.maxMatches,
                includePaginationLinks: request.includePaginationLinks
            )
            let result = try await webView.evaluateJavaScript(script)
            guard let dict = result as? [String: Any] else {
                throw AgentError.javascriptError("collectLinks: Invalid response format")
            }
            let responseData = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(LinkCollectionResult.self, from: responseData)
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.javascriptError(error.localizedDescription)
        }
    }

    // MARK: - Click

    /// Click an element by its agent ID, optionally with modifier keys
    func click(elementId: Int, modifiers: ClickModifiers = .none) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        lastInteractedElementId = elementId

        let script = AgentScripts.click(
            elementId: elementId,
            shiftKey: modifiers.shift,
            metaKey: modifiers.command,
            ctrlKey: modifiers.control,
            altKey: modifiers.option,
            hasModifiers: modifiers != .none
        )

        do {
            let result = try await webView.evaluateJavaScript(script)

            guard let dict = result as? [String: Any] else {
                throw AgentError.clickFailed("JavaScript execution returned no result (element ID: \(elementId)). The page may be unresponsive.")
            }

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

        lastInteractedElementId = elementId

        let escapedText = JavaScriptEscaper.escape(text)
        let script = AgentScripts.type(elementId: elementId, escapedText: escapedText)

        do {
            let result = try await webView.evaluateJavaScript(script)

            guard let dict = result as? [String: Any] else {
                throw AgentError.typeFailed("JavaScript execution returned no result (element ID: \(elementId)). The page may be unresponsive.")
            }

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

        let script = AgentScripts.pressEnter(elementSelector: elementSelector)

        do {
            let result = try await webView.evaluateJavaScript(script)

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

        do {
            _ = try await webView.evaluateJavaScript(AgentScripts.scroll(deltaX: deltaX, deltaY: deltaY))
        } catch {
            throw AgentError.scrollFailed(error.localizedDescription)
        }
    }

    /// Scroll to top of page
    func scrollToTop() async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        do {
            _ = try await webView.evaluateJavaScript(AgentScripts.scrollToTop)
        } catch {
            throw AgentError.scrollFailed(error.localizedDescription)
        }
    }

    /// Scroll to bottom of page
    func scrollToBottom() async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        do {
            _ = try await webView.evaluateJavaScript(AgentScripts.scrollToBottom)
        } catch {
            throw AgentError.scrollFailed(error.localizedDescription)
        }
    }

    // MARK: - Wait

    /// Wait for the page to finish loading with DOM stability detection for SPAs
    func waitForLoad(timeout: TimeInterval = 5.0, stableThreshold: TimeInterval = 0.5) async throws {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        let startTime = Date()
        var lastElementCount: Int? = nil
        var lastChangeTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if webView.isLoading {
                try await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            let currentCount = await getInteractiveElementCount()

            // Skip invalid readings (-1 means WebView error)
            guard currentCount >= 0 else {
                Log.Agent.debug("waitForLoad: getInteractiveElementCount returned -1, skipping")
                try await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            if currentCount != lastElementCount {
                lastElementCount = currentCount
                lastChangeTime = Date()
            } else if Date().timeIntervalSince(lastChangeTime) >= stableThreshold {
                return
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Capture a lightweight pre-action state for delta comparison
    func capturePreActionState() async -> (url: String, title: String, elementCount: Int, captchaDetected: Bool) {
        guard let webView = webView else {
            return ("", "", -1, false)
        }

        do {
            let result = try await webView.evaluateJavaScript(AgentScripts.capturePreActionState)
            guard let dict = result as? [String: Any] else {
                return ("", "", -1, false)
            }
            return (
                url: dict["url"] as? String ?? "",
                title: dict["title"] as? String ?? "",
                elementCount: dict["elementCount"] as? Int ?? -1,
                captchaDetected: dict["captchaDetected"] as? Bool ?? false
            )
        } catch {
            return ("", "", -1, false)
        }
    }

    /// Compute what changed between pre-action state and current page state
    func quickDelta(before: (url: String, title: String, elementCount: Int, captchaDetected: Bool)) async -> ActionDelta {
        let after = await capturePreActionState()
        return ActionDelta(
            urlChanged: before.url != after.url,
            newURL: before.url != after.url ? after.url : nil,
            titleChanged: before.title != after.title,
            newTitle: before.title != after.title ? after.title : nil,
            elementCountBefore: before.elementCount,
            elementCountAfter: after.elementCount,
            captchaAppeared: !before.captchaDetected && after.captchaDetected,
            captchaDisappeared: before.captchaDetected && !after.captchaDetected
        )
    }

    /// Get the count of interactive elements on the page
    func getInteractiveElementCount() async -> Int {
        guard let webView = webView else {
            Log.Agent.debug("getInteractiveElementCount: WebView is nil")
            return -1
        }

        do {
            let result = try await webView.evaluateJavaScript(AgentScripts.interactiveElementCount)
            return (result as? Int) ?? -1
        } catch {
            Log.Agent.debug("getInteractiveElementCount: JS error: \(error.localizedDescription)")
            return -1
        }
    }

    // MARK: - Get Page Text

    /// Get the main text content of the page
    func getPageText() async throws -> String {
        guard let webView = webView else {
            throw AgentError.webViewUnavailable
        }

        do {
            let result = try await webView.evaluateJavaScript(AgentScripts.pageText)
            return (result as? String) ?? ""
        } catch {
            throw AgentError.javascriptError(error.localizedDescription)
        }
    }
}
