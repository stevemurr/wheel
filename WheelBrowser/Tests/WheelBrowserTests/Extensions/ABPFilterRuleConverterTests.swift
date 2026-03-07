import Foundation
import Testing
@testable import WheelBrowser

@Suite("ABPFilterRuleConverter Tests")
struct ABPFilterRuleConverterTests {
    @Test("Converts basic block, exception, and cosmetic rules")
    func convertsSupportedRules() throws {
        let result = ABPFilterRuleConverter.convert(
            filterText: """
            ||ads.example.com^
            @@||ads.example.com^$domain=example.com|~media.example.com,script
            example.com##.ad-banner
            """,
            allowlistedDomains: ["allow.example.com"]
        )

        let rules = try #require(
            JSONSerialization.jsonObject(with: Data(result.encodedRuleList.utf8)) as? [[String: Any]]
        )

        #expect(result.ruleCount == 3)
        #expect(result.skippedRuleCount == 0)

        let firstAction = try #require(rules.first?["action"] as? [String: Any])
        #expect(firstAction["type"] as? String == "block")

        let exceptionAction = try #require(rules[1]["action"] as? [String: Any])
        let exceptionTrigger = try #require(rules[1]["trigger"] as? [String: Any])
        #expect(exceptionAction["type"] as? String == "ignore-previous-rules")
        #expect((exceptionTrigger["if-domain"] as? [String])?.contains("example.com") == true)
        #expect((exceptionTrigger["unless-domain"] as? [String])?.contains("allow.example.com") == true)

        let cosmeticAction = try #require(rules[2]["action"] as? [String: Any])
        #expect(cosmeticAction["type"] as? String == "css-display-none")
        #expect(cosmeticAction["selector"] as? String == ".ad-banner")
    }

    @Test("Unsupported options are skipped with diagnostics")
    func skipsUnsupportedRules() {
        let result = ABPFilterRuleConverter.convert(
            filterText: "||example.com^$redirect=noopjs",
            allowlistedDomains: []
        )

        #expect(result.ruleCount == 0)
        #expect(result.diagnostics.contains(where: { $0.contains("redirect") }))
    }
}
