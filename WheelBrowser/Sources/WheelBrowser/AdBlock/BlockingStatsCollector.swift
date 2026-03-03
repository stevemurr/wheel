import Foundation
import WebKit

/// Per-page blocking statistics collected from JavaScript
struct PageBlockingStats {
    var blockedRequests: Int = 0
    var hiddenElements: Int = 0
    var defusedScripts: Int = 0

    var totalBlocked: Int { blockedRequests + hiddenElements + defusedScripts }
}

/// Collects real blocking statistics from JavaScript via WKScriptMessageHandler.
///
/// Injects a lightweight script that listens for resource `error` events (indicating
/// blocked network requests) and receives counts from the cosmetic filter and
/// scriptlet injection engines.
@MainActor
class BlockingStatsCollector {

    static let shared = BlockingStatsCollector()

    /// Whether we've received real stats for the current session
    @Published private(set) var hasRealStats: Bool = false

    private init() {}

    /// Creates the stats collection user script, injected at document end
    static func createUserScript() -> WKUserScript {
        WKUserScript(
            source: statsScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Handle incoming stats message from JS
    func handleMessage(_ body: [String: Any], for domain: String) {
        let blocked = body["blocked"] as? Int ?? 0
        let hidden = body["hidden"] as? Int ?? 0
        let scriptlets = body["scriptlets"] as? Int ?? 0

        let stats = PageBlockingStats(
            blockedRequests: blocked,
            hiddenElements: hidden,
            defusedScripts: scriptlets
        )

        guard stats.totalBlocked > 0 else { return }

        hasRealStats = true

        // Forward real stats to BlockingStats
        BlockingStats.shared.recordRealPageStats(stats)
    }

    // MARK: - Script

    private static let statsScript = """
    (function() {
        'use strict';
        if (window.__wheelBlockingStats) return;

        var stats = { blocked: 0, hidden: 0, scriptlets: 0 };

        // Listen for resource load errors (likely blocked by content blocker)
        document.addEventListener('error', function(e) {
            var tag = e.target.tagName;
            if (tag === 'SCRIPT' || tag === 'IMG' || tag === 'IFRAME' ||
                tag === 'LINK' || tag === 'VIDEO' || tag === 'AUDIO') {
                stats.blocked++;
            }
        }, true);

        function reportStats() {
            try {
                window.webkit.messageHandlers.blockingStats.postMessage(stats);
            } catch(e) {}
        }

        window.__wheelBlockingStats = {
            reportHidden: function(count) {
                stats.hidden += count;
            },
            reportScriptletBlock: function() {
                stats.scriptlets++;
            },
            getStats: function() {
                return stats;
            }
        };

        // Report final stats after page settles
        window.addEventListener('load', function() {
            setTimeout(reportStats, 2000);
        });
    })();
    """
}
