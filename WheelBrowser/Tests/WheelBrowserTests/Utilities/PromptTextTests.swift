import Testing
@testable import WheelBrowser

@Suite("PromptText")
struct PromptTextTests {
    @Test("Normalization collapses punctuation and optionally preserves slashes")
    func normalization() {
        #expect(PromptText.normalize("r/Swift-Lang News!", preservingSlash: true) == "r/swift lang news")
        #expect(PromptText.normalize("r/Swift-Lang News!", preservingSlash: false) == "r swift lang news")
    }

    @Test("Word and phrase matching operate on normalized prompts")
    func wordAndPhraseMatching() {
        let prompt = PromptText.normalize("Top stories on Hacker News")

        #expect(PromptText.containsPhrase("hacker news", in: prompt))
        #expect(PromptText.containsWord("stories", in: prompt))
        #expect(!PromptText.containsWord("story", in: PromptText.normalize("storyline review")))
        #expect(!PromptText.containsWord("news", in: PromptText.normalize("newsletter digest")))
    }

    @Test("Integer extraction uses caller-provided bounds")
    func integerExtraction() {
        let prompt = PromptText.normalize("show me the top 12 stories")

        #expect(PromptText.extractInteger(in: #"\b([1-9]|1[0-9]|20)\b"#, from: prompt) == 12)
        #expect(PromptText.extractInteger(in: #"\b([1-5])\b"#, from: prompt) == nil)
    }

    @Test("Deduplication preserves first occurrence order")
    func deduplicationPreservesOrder() {
        #expect(PromptText.deduplicated(["tokyo", "nyc", "tokyo", "london", "nyc"]) == ["tokyo", "nyc", "london"])
    }

    @Test("Widget prompt factories still resolve representative prompts")
    func widgetPromptFactoriesStillResolveRepresentativePrompts() throws {
        let clockManifest = try #require(WidgetPromptTemplateFactory.manifest(for: "show time in New York and Tokyo"))
        let hackerNewsPlan = try #require(WidgetPromptPlanFactory.plan(for: "top 3 hacker news stories"))
        let subredditPlan = try #require(WidgetPromptPlanFactory.plan(for: "latest 4 posts on r/swift"))

        #expect(clockManifest.skillChain.count == 3)
        #expect(hackerNewsPlan.title == "Top 3 Hacker News Stories")
        #expect(subredditPlan.title == "Latest Posts on r/swift")
        #expect(subredditPlan.list?.maxItems == 4)
    }
}
