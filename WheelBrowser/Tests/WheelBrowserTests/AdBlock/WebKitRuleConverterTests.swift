import Testing
@testable import WheelBrowser

@Suite("WebKitRuleConverter Tests")
struct WebKitRuleConverterTests {

    let converter = WebKitRuleConverter()

    // MARK: - URL Block Rule Conversion

    @Test("Converts simple URL block rule")
    func convertsSimpleURLBlock() {
        let rule = URLBlockRule(
            pattern: "example.com/ads",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: false,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])

        #expect(result.count == 1)
        let trigger = result[0]["trigger"] as? [String: Any]
        let action = result[0]["action"] as? [String: Any]

        #expect(trigger?["url-filter"] != nil)
        #expect(action?["type"] as? String == "block")
    }

    @Test("Converts domain anchor to regex prefix")
    func convertsDomainAnchor() {
        let rule = URLBlockRule(
            pattern: "example.com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let urlFilter = trigger?["url-filter"] as? String

        // Domain anchor should start with pattern matching https:// and optional subdomain
        #expect(urlFilter?.hasPrefix("^https?://") == true)
    }

    @Test("Converts address start anchor")
    func convertsAddressStartAnchor() {
        let rule = URLBlockRule(
            pattern: "https://example.com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: false,
            isAddressStartAnchor: true,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let urlFilter = trigger?["url-filter"] as? String

        #expect(urlFilter?.hasPrefix("^") == true)
    }

    @Test("Converts address end anchor")
    func convertsAddressEndAnchor() {
        let rule = URLBlockRule(
            pattern: "example.com/page",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: false,
            isAddressStartAnchor: false,
            isAddressEndAnchor: true,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let urlFilter = trigger?["url-filter"] as? String

        #expect(urlFilter?.hasSuffix("$") == true)
    }

    // MARK: - Resource Types

    @Test("Adds resource types to trigger")
    func addsResourceTypes() {
        let rule = URLBlockRule(
            pattern: "ads.com",
            resourceTypes: [.script, .image],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let resourceTypes = trigger?["resource-type"] as? [String]

        #expect(resourceTypes?.contains("script") == true)
        #expect(resourceTypes?.contains("image") == true)
    }

    // MARK: - Load Types

    @Test("Adds third-party load type")
    func addsThirdPartyLoadType() {
        let rule = URLBlockRule(
            pattern: "ads.com",
            resourceTypes: [],
            loadType: .thirdParty,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let loadType = trigger?["load-type"] as? [String]

        #expect(loadType == ["third-party"])
    }

    @Test("Adds first-party load type")
    func addsFirstPartyLoadType() {
        let rule = URLBlockRule(
            pattern: "ads.com",
            resourceTypes: [],
            loadType: .firstParty,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let loadType = trigger?["load-type"] as? [String]

        #expect(loadType == ["first-party"])
    }

    @Test("No load-type for all")
    func noLoadTypeForAll() {
        let rule = URLBlockRule(
            pattern: "ads.com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]

        #expect(trigger?["load-type"] == nil)
    }

    // MARK: - Domain Conditions

    @Test("Formats if-domain with wildcard prefix")
    func formatsIfDomain() {
        let rule = URLBlockRule(
            pattern: "ads.com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: ["example.com", "test.com"],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let ifDomain = trigger?["if-domain"] as? [String]

        #expect(ifDomain?.contains("*example.com") == true)
        #expect(ifDomain?.contains("*test.com") == true)
    }

    @Test("Formats unless-domain with wildcard prefix")
    func formatsUnlessDomain() {
        let rule = URLBlockRule(
            pattern: "ads.com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: ["excluded.com"],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]
        let unlessDomain = trigger?["unless-domain"] as? [String]

        #expect(unlessDomain?.contains("*excluded.com") == true)
    }

    // MARK: - Case Sensitivity

    @Test("Adds case sensitivity flag")
    func addsCaseSensitivity() {
        let rule = URLBlockRule(
            pattern: "Ads.Com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: true
        )

        let result = converter.convert([.urlBlock(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]

        #expect(trigger?["url-filter-is-case-sensitive"] as? Bool == true)
    }

    // MARK: - Exception Rules

    @Test("Converts exception rule with ignore-previous-rules action")
    func convertsExceptionRule() {
        let rule = URLBlockRule(
            pattern: "allowed.com",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: true,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlException(rule)])
        let action = result[0]["action"] as? [String: Any]

        #expect(action?["type"] as? String == "ignore-previous-rules")
    }

    // MARK: - CSS Rules

    @Test("Converts CSS hide rule to css-display-none")
    func convertsCSSHideRule() {
        let rule = CSSHideRule(
            selector: ".ad-banner",
            includeDomains: ["example.com"],
            excludeDomains: []
        )

        let result = converter.convert([.cssHide(rule)])
        let action = result[0]["action"] as? [String: Any]

        #expect(action?["type"] as? String == "css-display-none")
        #expect(action?["selector"] as? String == ".ad-banner")
    }

    @Test("CSS hide rule uses catch-all URL filter")
    func cssHideUsesCatchAllFilter() {
        let rule = CSSHideRule(
            selector: ".ad",
            includeDomains: [],
            excludeDomains: []
        )

        let result = converter.convert([.cssHide(rule)])
        let trigger = result[0]["trigger"] as? [String: Any]

        #expect(trigger?["url-filter"] as? String == ".*")
    }

    @Test("CSS exception uses ignore-previous-rules")
    func cssExceptionUsesIgnore() {
        let rule = CSSHideRule(
            selector: ".ad",
            includeDomains: ["example.com"],
            excludeDomains: []
        )

        let result = converter.convert([.cssException(rule)])
        let action = result[0]["action"] as? [String: Any]

        #expect(action?["type"] as? String == "ignore-previous-rules")
    }

    // MARK: - Selector Validation

    @Test("Rejects selector with :has()")
    func rejectsSelectorWithHas() {
        let rule = CSSHideRule(
            selector: ".ad:has(.text)",
            includeDomains: [],
            excludeDomains: []
        )

        let result = converter.convert([.cssHide(rule)])
        #expect(result.isEmpty)
    }

    @Test("Rejects selector with :is()")
    func rejectsSelectorWithIs() {
        let rule = CSSHideRule(
            selector: ":is(.ad, .banner)",
            includeDomains: [],
            excludeDomains: []
        )

        let result = converter.convert([.cssHide(rule)])
        #expect(result.isEmpty)
    }

    @Test("Rejects procedural selectors")
    func rejectsProceduralSelectors() {
        let selectors = [
            ".ad:contains(Advertisement)",
            ".ad:has-text(Sponsored)",
            "div:xpath(//div[@class='ad'])",
            "div:-abp-contains(ad)",
            ".ad:style(display: none)"
        ]

        for selector in selectors {
            let rule = CSSHideRule(
                selector: selector,
                includeDomains: [],
                excludeDomains: []
            )
            let result = converter.convert([.cssHide(rule)])
            #expect(result.isEmpty, "Should reject selector: \(selector)")
        }
    }

    // MARK: - Comments and Unsupported

    @Test("Skips comments")
    func skipsComments() {
        let result = converter.convert([.comment("! This is a comment")])
        #expect(result.isEmpty)
    }

    @Test("Skips unsupported rules")
    func skipsUnsupported() {
        let result = converter.convert([.unsupported("some#?#complex:rule")])
        #expect(result.isEmpty)
    }

    // MARK: - Limits

    @Test("Respects max rules limit")
    func respectsMaxRulesLimit() {
        var rules: [ABPRule] = []
        for i in 0..<100 {
            let urlRule = URLBlockRule(
                pattern: "site\(i).com",
                resourceTypes: [],
                loadType: .all,
                includeDomains: [],
                excludeDomains: [],
                isDomainAnchor: true,
                isAddressStartAnchor: false,
                isAddressEndAnchor: false,
                matchCase: false
            )
            rules.append(.urlBlock(urlRule))
        }

        let result = converter.convert(rules, maxRules: 50)
        #expect(result.count == 50)
    }

    // MARK: - Pattern Validation

    @Test("Rejects empty pattern")
    func rejectsEmptyPattern() {
        let rule = URLBlockRule(
            pattern: "",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: false,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        #expect(result.isEmpty)
    }

    @Test("Rejects wildcard-only pattern")
    func rejectsWildcardOnlyPattern() {
        let rule = URLBlockRule(
            pattern: "*",
            resourceTypes: [],
            loadType: .all,
            includeDomains: [],
            excludeDomains: [],
            isDomainAnchor: false,
            isAddressStartAnchor: false,
            isAddressEndAnchor: false,
            matchCase: false
        )

        let result = converter.convert([.urlBlock(rule)])
        #expect(result.isEmpty)
    }

    // MARK: - Conversion Statistics

    @Test("convertWithStats returns correct statistics")
    func convertWithStatsReturnsCorrectStats() {
        let rules: [ABPRule] = [
            .urlBlock(URLBlockRule(
                pattern: "ads.com",
                resourceTypes: [],
                loadType: .all,
                includeDomains: [],
                excludeDomains: [],
                isDomainAnchor: true,
                isAddressStartAnchor: false,
                isAddressEndAnchor: false,
                matchCase: false
            )),
            .urlException(URLBlockRule(
                pattern: "allowed.com",
                resourceTypes: [],
                loadType: .all,
                includeDomains: [],
                excludeDomains: [],
                isDomainAnchor: true,
                isAddressStartAnchor: false,
                isAddressEndAnchor: false,
                matchCase: false
            )),
            .cssHide(CSSHideRule(selector: ".ad", includeDomains: [], excludeDomains: [])),
            .comment("! comment"),
            .unsupported("unsupported")
        ]

        let (converted, stats) = converter.convertWithStats(rules)

        #expect(converted.count == 3)
        #expect(stats.urlBlockConverted == 1)
        #expect(stats.urlExceptionConverted == 1)
        #expect(stats.cssHideConverted == 1)
        #expect(stats.comments == 1)
        #expect(stats.unsupported == 1)
        #expect(stats.totalConverted == 3)
    }
}
