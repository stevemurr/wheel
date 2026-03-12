import Testing
@testable import WheelBrowser

@Suite("ChatResponseContinuation")
struct ChatResponseContinuationTests {
    @Test("Detects orphan markdown tail markers")
    func detectsOrphanMarkdownTailMarkers() {
        #expect(
            ChatResponseContinuation.shouldRequestContinuation(
                for: """
                Typical workflow

                1. Define constants
                2. **
                """
            )
        )
    }

    @Test("Leaves complete markdown answers alone")
    func ignoresCompleteMarkdownAnswers() {
        #expect(
            ChatResponseContinuation.shouldRequestContinuation(
                for: """
                Typical workflow

                1. Define constants
                2. **State variables**
                3. Write definitions.
                """
            ) == false
        )
    }

    @Test("Merges overlapping continuations without duplication")
    func mergesOverlappingContinuations() {
        let merged = ChatResponseContinuation.merge(
            base: "2. **",
            continuation: "**State variables**"
        )

        #expect(merged == "2. **State variables**")
    }
}
