import Foundation
import WebKit

/// Manages per-site content blocking exceptions using WebKit's `ignore-previous-rules` action.
///
/// When a domain is allowlisted, a single `WKContentRuleList` is compiled with an
/// `ignore-previous-rules` action scoped to those domains via `if-domain`. This rule list
/// must be applied **after** all blocking rule lists so that it overrides them.
@MainActor
class SiteAllowlistManager: ObservableObject {

    static let shared = SiteAllowlistManager()

    /// Domains currently on the allowlist
    @Published private(set) var allowlistedDomains: Set<String> {
        didSet { saveDomains() }
    }

    /// Compiled allowlist rule list (nil when no domains are allowlisted)
    private var allowlistRuleList: WKContentRuleList?

    private let domainsKey = "SiteAllowlistDomains"
    private let ruleListIdentifier = "WheelBrowser-site-allowlist"

    private let compilationPipeline = RuleCompilationPipeline()

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: domainsKey) ?? []
        self.allowlistedDomains = Set(saved)
    }

    // MARK: - Domain Management

    func addDomain(_ domain: String) async {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return }
        allowlistedDomains.insert(normalized)
        await recompile()
    }

    func removeDomain(_ domain: String) async {
        let normalized = normalizeDomain(domain)
        allowlistedDomains.remove(normalized)
        await recompile()
    }

    func toggleDomain(_ domain: String) async {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return }
        if allowlistedDomains.contains(normalized) {
            allowlistedDomains.remove(normalized)
        } else {
            allowlistedDomains.insert(normalized)
        }
        await recompile()
    }

    func isDomainAllowlisted(_ domain: String?) -> Bool {
        guard let domain = domain else { return false }
        let normalized = normalizeDomain(domain)
        // Check exact match and parent domains
        let parts = normalized.split(separator: ".")
        for i in 0..<parts.count {
            let candidate = parts[i...].joined(separator: ".")
            if allowlistedDomains.contains(candidate) {
                return true
            }
        }
        return false
    }

    // MARK: - Rule Application

    /// Apply the allowlist rule to a WKWebView (must be called AFTER all blocking rules)
    func applyAllowlist(to webView: WKWebView) {
        guard let ruleList = allowlistRuleList else { return }
        webView.configuration.userContentController.add(ruleList)
    }

    /// Apply the allowlist rule to a configuration (must be called AFTER all blocking rules)
    func applyAllowlist(to configuration: WKWebViewConfiguration) {
        guard let ruleList = allowlistRuleList else { return }
        configuration.userContentController.add(ruleList)
    }

    /// Remove the allowlist rule from a WKWebView
    func removeAllowlist(from webView: WKWebView) {
        guard let ruleList = allowlistRuleList else { return }
        webView.configuration.userContentController.remove(ruleList)
    }

    // MARK: - Compilation

    /// Recompile the allowlist rule from the current set of domains
    func recompile() async {
        // Remove old compiled list from WebKit store
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().removeContentRuleList(
                forIdentifier: ruleListIdentifier
            ) { _ in
                continuation.resume()
            }
        }

        allowlistRuleList = nil

        guard !allowlistedDomains.isEmpty else { return }

        // Build a single ignore-previous-rules entry scoped to allowlisted domains
        let rule: [String: Any] = [
            "trigger": [
                "url-filter": ".*",
                "if-domain": allowlistedDomains.sorted().map { "*\($0)" }
            ],
            "action": [
                "type": "ignore-previous-rules"
            ]
        ]

        do {
            let compiled = try await compilationPipeline.compile([rule], identifier: ruleListIdentifier)
            allowlistRuleList = compiled
        } catch {
            Log.AdBlock.error("Failed to compile site allowlist: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func normalizeDomain(_ domain: String) -> String {
        var d = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading www.
        if d.hasPrefix("www.") {
            d = String(d.dropFirst(4))
        }
        return d
    }

    private func saveDomains() {
        UserDefaults.standard.set(Array(allowlistedDomains), forKey: domainsKey)
    }
}
