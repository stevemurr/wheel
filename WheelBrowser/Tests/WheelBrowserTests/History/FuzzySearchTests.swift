import Testing
@testable import WheelBrowser

@Suite("FuzzySearch Tests")
struct FuzzySearchTests {

    // MARK: - score() Tests

    @Test("Exact match returns 1000")
    func exactMatchScore() {
        let score = FuzzySearch.score(query: "hello", target: "hello")
        #expect(score == 1000)
    }

    @Test("Exact match is case insensitive")
    func exactMatchCaseInsensitive() {
        let score = FuzzySearch.score(query: "Hello", target: "HELLO")
        #expect(score == 1000)
    }

    @Test("Prefix match returns 800")
    func prefixMatchScore() {
        let score = FuzzySearch.score(query: "goo", target: "google.com")
        #expect(score == 800)
    }

    @Test("Separator-adjacent match returns 700")
    func separatorAdjacentMatchScore() {
        // Match after ://
        let score1 = FuzzySearch.score(query: "example", target: "https://example.com")
        #expect(score1 == 700)

        // Match after /
        let score2 = FuzzySearch.score(query: "path", target: "example.com/path")
        #expect(score2 == 700)

        // Match after .
        let score3 = FuzzySearch.score(query: "com", target: "example.com")
        #expect(score3 == 700)
    }

    @Test("Substring match returns 600")
    func substringMatchScore() {
        let score = FuzzySearch.score(query: "xam", target: "example.com")
        #expect(score == 600)
    }

    @Test("Empty query returns 0")
    func emptyQueryScore() {
        let score = FuzzySearch.score(query: "", target: "hello")
        #expect(score == 0)
    }

    @Test("Empty target returns 0")
    func emptyTargetScore() {
        let score = FuzzySearch.score(query: "hello", target: "")
        #expect(score == 0)
    }

    @Test("Query longer than target returns 0")
    func queryLongerThanTarget() {
        let score = FuzzySearch.score(query: "hello world", target: "hi")
        #expect(score == 0)
    }

    @Test("No match returns 0")
    func noMatchScore() {
        let score = FuzzySearch.score(query: "xyz", target: "hello")
        #expect(score == 0)
    }

    @Test("Fuzzy match with consecutive characters gets bonus")
    func fuzzyMatchConsecutiveBonus() {
        // "git" in "github" - consecutive characters
        let consecutiveScore = FuzzySearch.score(query: "git", target: "github")
        // "git" in "gaitlib" - spread out characters
        let spreadScore = FuzzySearch.score(query: "git", target: "gaitlib")

        // Both should match but consecutive should score higher
        #expect(consecutiveScore > 0)
        #expect(spreadScore > 0)
        #expect(consecutiveScore > spreadScore)
    }

    @Test("Word boundary match gets bonus")
    func wordBoundaryBonus() {
        // Match at start of target
        let startScore = FuzzySearch.score(query: "ab", target: "abstract")
        // Match at start of word after separator
        let wordBoundaryScore = FuzzySearch.score(query: "ab", target: "the-abstract")

        #expect(startScore > 0)
        #expect(wordBoundaryScore > 0)
    }

    @Test("Fuzzy match requires all characters to be present")
    func fuzzyMatchAllCharactersRequired() {
        // "gth" can be found in "github" (g-i-t-h-u-b)
        let matchScore = FuzzySearch.score(query: "gth", target: "github")
        // "gxh" cannot be found
        let noMatchScore = FuzzySearch.score(query: "gxh", target: "github")

        #expect(matchScore > 0)
        #expect(noMatchScore == 0)
    }

    // MARK: - filter() Tests

    struct TestItem: Equatable {
        let name: String
    }

    @Test("Filter returns empty query items with limit")
    func filterEmptyQuery() {
        let items = [
            TestItem(name: "apple"),
            TestItem(name: "banana"),
            TestItem(name: "cherry")
        ]

        let result = FuzzySearch.filter(items: items, query: "", keyPath: \.name, limit: 2)
        #expect(result.count == 2)
        #expect(result[0] == items[0])
        #expect(result[1] == items[1])
    }

    @Test("Filter returns matching items sorted by score")
    func filterSortedByScore() {
        let items = [
            TestItem(name: "application"),
            TestItem(name: "apple"),
            TestItem(name: "pineapple")
        ]

        let result = FuzzySearch.filter(items: items, query: "apple", keyPath: \.name)

        // "apple" should be first (exact match = 1000)
        // "pineapple" should be second (contains match)
        // "application" may or may not match depending on algorithm
        #expect(result.count >= 2)
        #expect(result[0].name == "apple")
    }

    @Test("Filter respects limit")
    func filterRespectsLimit() {
        let items = (1...20).map { TestItem(name: "item\($0)") }
        let result = FuzzySearch.filter(items: items, query: "item", keyPath: \.name, limit: 5)
        #expect(result.count == 5)
    }

    @Test("Filter excludes non-matching items")
    func filterExcludesNonMatching() {
        let items = [
            TestItem(name: "apple"),
            TestItem(name: "banana"),
            TestItem(name: "cherry")
        ]

        let result = FuzzySearch.filter(items: items, query: "app", keyPath: \.name)
        #expect(result.count == 1)
        #expect(result[0].name == "apple")
    }

    @Test("Filter handles no matches")
    func filterNoMatches() {
        let items = [
            TestItem(name: "apple"),
            TestItem(name: "banana")
        ]

        let result = FuzzySearch.filter(items: items, query: "xyz", keyPath: \.name)
        #expect(result.isEmpty)
    }
}
