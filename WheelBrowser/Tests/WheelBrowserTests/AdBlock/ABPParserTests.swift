import Testing
@testable import WheelBrowser

@Suite("ABPParser Tests")
struct ABPParserTests {

    // MARK: - Comment Parsing

    @Test("Parses comment lines starting with !")
    func parsesCommentWithExclamation() async {
        let parser = ABPParser()
        let rules = await parser.parse("! This is a comment")

        #expect(rules.count == 1)
        if case .comment(let text) = rules[0] {
            #expect(text == "! This is a comment")
        } else {
            Issue.record("Expected comment rule")
        }
    }

    @Test("Parses Adblock header as comment")
    func parsesAdblockHeader() async {
        let parser = ABPParser()
        let rules = await parser.parse("[Adblock Plus 2.0]")

        #expect(rules.count == 1)
        if case .comment = rules[0] {
            // Success
        } else {
            Issue.record("Expected comment rule for Adblock header")
        }
    }

    // MARK: - URL Block Rules

    @Test("Parses simple URL block rule")
    func parsesSimpleURLBlock() async {
        let parser = ABPParser()
        let rules = await parser.parse("example.com/ads")

        #expect(rules.count == 1)
        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.pattern == "example.com/ads")
            #expect(rule.isDomainAnchor == false)
            #expect(rule.isAddressStartAnchor == false)
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses domain anchor rule (||)")
    func parsesDomainAnchor() async {
        let parser = ABPParser()
        let rules = await parser.parse("||example.com^")

        #expect(rules.count == 1)
        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.pattern == "example.com^")
            #expect(rule.isDomainAnchor == true)
        } else {
            Issue.record("Expected urlBlock rule with domain anchor")
        }
    }

    @Test("Parses address start anchor (|)")
    func parsesAddressStartAnchor() async {
        let parser = ABPParser()
        let rules = await parser.parse("|https://example.com")

        #expect(rules.count == 1)
        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.isAddressStartAnchor == true)
            #expect(rule.isDomainAnchor == false)
        } else {
            Issue.record("Expected urlBlock rule with start anchor")
        }
    }

    @Test("Parses address end anchor (|)")
    func parsesAddressEndAnchor() async {
        let parser = ABPParser()
        let rules = await parser.parse("example.com/page|")

        #expect(rules.count == 1)
        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.isAddressEndAnchor == true)
        } else {
            Issue.record("Expected urlBlock rule with end anchor")
        }
    }

    // MARK: - URL Exception Rules

    @Test("Parses URL exception rule (@@)")
    func parsesURLException() async {
        let parser = ABPParser()
        let rules = await parser.parse("@@||example.com^")

        #expect(rules.count == 1)
        if case .urlException(let rule) = rules[0] {
            #expect(rule.pattern == "example.com^")
            #expect(rule.isDomainAnchor == true)
        } else {
            Issue.record("Expected urlException rule")
        }
    }

    // MARK: - Options Parsing

    @Test("Parses third-party option")
    func parsesThirdPartyOption() async {
        let parser = ABPParser()
        let rules = await parser.parse("||example.com^$third-party")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.loadType == .thirdParty)
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses first-party option")
    func parsesFirstPartyOption() async {
        let parser = ABPParser()
        let rules = await parser.parse("||example.com^$first-party")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.loadType == .firstParty)
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses negated third-party as first-party")
    func parsesNegatedThirdParty() async {
        let parser = ABPParser()
        let rules = await parser.parse("||example.com^$~third-party")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.loadType == .firstParty)
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses resource type options")
    func parsesResourceTypeOptions() async {
        let parser = ABPParser()
        let rules = await parser.parse("||example.com^$script,image")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.resourceTypes.contains(.script))
            #expect(rule.resourceTypes.contains(.image))
            #expect(!rule.resourceTypes.contains(.stylesheet))
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses domain option with include domains")
    func parsesDomainOptionInclude() async {
        let parser = ABPParser()
        let rules = await parser.parse("||ads.com^$domain=example.com|test.com")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.includeDomains.contains("example.com"))
            #expect(rule.includeDomains.contains("test.com"))
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses domain option with exclude domains")
    func parsesDomainOptionExclude() async {
        let parser = ABPParser()
        let rules = await parser.parse("||ads.com^$domain=~excluded.com")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.excludeDomains.contains("excluded.com"))
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    @Test("Parses match-case option")
    func parsesMatchCaseOption() async {
        let parser = ABPParser()
        let rules = await parser.parse("||Example.com^$match-case")

        if case .urlBlock(let rule) = rules[0] {
            #expect(rule.matchCase == true)
        } else {
            Issue.record("Expected urlBlock rule")
        }
    }

    // MARK: - CSS Hide Rules

    @Test("Parses CSS hide rule with ##")
    func parsesCSSHide() async {
        let parser = ABPParser()
        let rules = await parser.parse("example.com##.ad-banner")

        #expect(rules.count == 1)
        if case .cssHide(let rule) = rules[0] {
            #expect(rule.selector == ".ad-banner")
            #expect(rule.includeDomains.contains("example.com"))
        } else {
            Issue.record("Expected cssHide rule")
        }
    }

    @Test("Parses CSS hide rule without domain (global)")
    func parsesCSSHideGlobal() async {
        let parser = ABPParser()
        let rules = await parser.parse("##.ad-banner")

        if case .cssHide(let rule) = rules[0] {
            #expect(rule.selector == ".ad-banner")
            #expect(rule.includeDomains.isEmpty)
        } else {
            Issue.record("Expected cssHide rule")
        }
    }

    @Test("Parses CSS hide rule with multiple domains")
    func parsesCSSHideMultipleDomains() async {
        let parser = ABPParser()
        let rules = await parser.parse("example.com,test.com##.ad")

        if case .cssHide(let rule) = rules[0] {
            #expect(rule.includeDomains.contains("example.com"))
            #expect(rule.includeDomains.contains("test.com"))
        } else {
            Issue.record("Expected cssHide rule")
        }
    }

    @Test("Parses CSS hide rule with excluded domains")
    func parsesCSSHideExcludedDomains() async {
        let parser = ABPParser()
        let rules = await parser.parse("~example.com##.ad")

        if case .cssHide(let rule) = rules[0] {
            #expect(rule.excludeDomains.contains("example.com"))
        } else {
            Issue.record("Expected cssHide rule")
        }
    }

    // MARK: - CSS Exception Rules

    @Test("Parses CSS exception rule with #@#")
    func parsesCSSException() async {
        let parser = ABPParser()
        let rules = await parser.parse("example.com#@#.ad-banner")

        #expect(rules.count == 1)
        if case .cssException(let rule) = rules[0] {
            #expect(rule.selector == ".ad-banner")
            #expect(rule.includeDomains.contains("example.com"))
        } else {
            Issue.record("Expected cssException rule")
        }
    }

    // MARK: - Unsupported Rules

    @Test("Marks extended CSS as unsupported")
    func marksExtendedCSSAsUnsupported() async {
        let parser = ABPParser()

        let rules1 = await parser.parse("example.com#?#.ad:has(.text)")
        if case .unsupported = rules1[0] {
            // Success
        } else {
            Issue.record("Expected unsupported for #?# rule")
        }

        let rules2 = await parser.parse("example.com#$#.ad { display: none; }")
        if case .unsupported = rules2[0] {
            // Success
        } else {
            Issue.record("Expected unsupported for #$# rule")
        }
    }

    @Test("Skips overly broad patterns")
    func skipsOverlyBroadPatterns() async {
        let parser = ABPParser()

        // Single wildcard
        let rules1 = await parser.parse("*")
        if case .unsupported = rules1[0] {
            // Success
        } else {
            Issue.record("Expected unsupported for single wildcard")
        }

        // Single separator
        let rules2 = await parser.parse("^")
        if case .unsupported = rules2[0] {
            // Success
        } else {
            Issue.record("Expected unsupported for single separator")
        }
    }

    // MARK: - Multi-line Parsing

    @Test("Parses multiple lines correctly")
    func parsesMultipleLines() async {
        let parser = ABPParser()
        let content = """
        ! Comment
        ||ads.com^
        ##.banner
        @@||allowed.com^
        """

        let rules = await parser.parse(content)

        #expect(rules.count == 4)

        if case .comment = rules[0] {} else {
            Issue.record("Expected comment at index 0")
        }
        if case .urlBlock = rules[1] {} else {
            Issue.record("Expected urlBlock at index 1")
        }
        if case .cssHide = rules[2] {} else {
            Issue.record("Expected cssHide at index 2")
        }
        if case .urlException = rules[3] {} else {
            Issue.record("Expected urlException at index 3")
        }
    }

    @Test("Skips empty lines")
    func skipsEmptyLines() async {
        let parser = ABPParser()
        let content = """
        ||ads.com^

        ||more.com^
        """

        let rules = await parser.parse(content)
        #expect(rules.count == 2)
    }

    // MARK: - Parser Statistics

    @Test("parseWithStats returns correct statistics")
    func parseWithStatsReturnsCorrectStats() async {
        let parser = ABPParser()
        let content = """
        ! Comment
        ||ads.com^
        ||block2.com^
        @@||allowed.com^
        ##.banner
        example.com#@#.exception
        example.com#?#unsupported
        """

        let (rules, stats) = await parser.parseWithStats(content)

        #expect(rules.count == 7)
        #expect(stats.comments == 1)
        #expect(stats.urlBlockRules == 2)
        #expect(stats.urlExceptionRules == 1)
        #expect(stats.cssHideRules == 1)
        #expect(stats.cssExceptionRules == 1)
        #expect(stats.unsupported == 1)
        #expect(stats.totalRules == 5) // Excludes comments and unsupported
    }
}
