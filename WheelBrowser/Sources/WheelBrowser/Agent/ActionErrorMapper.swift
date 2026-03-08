import Foundation

/// Maps technical error messages into instructive feedback the LLM can act on.
enum ActionErrorMapper {

    /// Map an error and the action that caused it into an LLM-friendly message.
    static func mapError(_ error: Error, action: AgentAction) -> String {
        let raw = error.localizedDescription

        // Element not found
        if raw.contains("Element not found") || raw.contains("not found") {
            return "Element disappeared since last snapshot. Take a fresh look at the page and use updated element IDs."
        }

        // Element not visible
        if raw.contains("no longer visible") {
            return "That element is no longer visible on the page. It may have been hidden or removed. Take a fresh snapshot and find an alternative."
        }

        // Not a text input
        if raw.contains("not a text input") || raw.contains("Element is not a text input") {
            return "That element cannot accept text. Look for an <input>, <textarea>, or contenteditable field instead."
        }

        // Page unresponsive
        if raw.contains("returned no result") || raw.contains("unresponsive") {
            return "The page appears unresponsive. Try waiting a moment with wait(2) then retry."
        }

        // Navigation failures
        if raw.contains("Failed to navigate") || raw.contains("navigation") {
            if case .navigate(let url) = action {
                return "Could not navigate to \(url). Verify the URL is correct and try again, or search for it instead."
            }
            if case .advancePagination(let url) = action {
                let destination = url ?? "the next page"
                return "Could not advance pagination to \(destination). Try a different pagination target or reassess the page."
            }
            return "Navigation failed. Try a different URL or use a search engine to find the page."
        }

        // Cannot go back
        if raw.contains("Cannot go back") || raw.contains("no history") {
            return "No browser history to go back to. Try navigating to a different page directly."
        }

        // WebView unavailable
        if raw.contains("WebView is not available") {
            return "The browser tab is not available. The tab may have been closed."
        }

        // JavaScript errors
        if raw.contains("JavaScript error") {
            return "A page script error occurred. The page may be in an unstable state. Try scrolling or clicking a different element."
        }

        // Tab closed
        if raw.contains("tab was closed") {
            return "The tab was closed while the action was in progress."
        }

        // Scroll failures
        if raw.contains("Failed to scroll") {
            return "Could not scroll the page. The page may not be scrollable in that direction."
        }

        // Fallback: return the original error with guidance prefix
        return "\(raw) Try a different approach."
    }
}
