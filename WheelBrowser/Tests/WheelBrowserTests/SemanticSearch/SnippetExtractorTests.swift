import Testing
@testable import WheelBrowser

@Suite("SnippetExtractor Tests")
struct SnippetExtractorTests {

    @Test("Returns sentence with most matching terms")
    func bestMatchingSentence() {
        let content = "The cat sat on the mat. The dog ran in the park. The cat and dog played together."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["cat", "dog"])
        #expect(result == "The cat and dog played together.")
    }

    @Test("Returns first sentence on tie")
    func tieBreaking() {
        let content = "The cat sat here. The dog sat there. The bird flew away."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["sat"])
        #expect(result == "The cat sat here.")
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        let content = "SWIFT is a programming language. Python is also popular."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["swift"])
        #expect(result == "SWIFT is a programming language.")
    }

    @Test("Returns nil when no terms match")
    func noMatch() {
        let content = "The cat sat on the mat. The dog ran in the park."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["elephant", "giraffe"])
        #expect(result == nil)
    }

    @Test("Returns nil for empty content")
    func emptyContent() {
        let result = SnippetExtractor.extractSnippet(from: "", queryTerms: ["test"])
        #expect(result == nil)
    }

    @Test("Returns nil for empty query terms")
    func emptyQueryTerms() {
        let result = SnippetExtractor.extractSnippet(from: "Hello world.", queryTerms: [])
        #expect(result == nil)
    }

    @Test("Handles single sentence content")
    func singleSentence() {
        let content = "The quick brown fox jumps over the lazy dog."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["fox"])
        #expect(result == "The quick brown fox jumps over the lazy dog.")
    }

    @Test("Handles multiple matching terms in one sentence")
    func multipleTermsOneSentence() {
        let content = "Apple released a new iPhone. Samsung released a new Galaxy. Apple and Samsung compete in the smartphone market."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["apple", "samsung", "market"])
        #expect(result == "Apple and Samsung compete in the smartphone market.")
    }

    @Test("Partial word matching works via contains")
    func partialWordMatch() {
        let content = "The programmer wrote code. The artist drew pictures."
        let result = SnippetExtractor.extractSnippet(from: content, queryTerms: ["program"])
        #expect(result == "The programmer wrote code.")
    }
}
