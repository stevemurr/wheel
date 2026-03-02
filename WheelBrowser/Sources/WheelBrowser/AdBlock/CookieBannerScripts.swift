import Foundation
import WebKit

/// JavaScript-based cookie banner auto-dismissal system.
/// Works in three layers:
/// 1. CSS display:none rules (in BlockingRules JSON resources) hide known banner selectors instantly
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

    private static let dismissalScript: String = {
        guard let url = Bundle.module.url(forResource: "cookie-banner-dismissal", withExtension: "js", subdirectory: "Scripts"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            Log.AdBlock.error("Failed to load cookie-banner-dismissal.js")
            return ""
        }
        return script
    }()
}
