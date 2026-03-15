import Testing
@testable import WheelBrowser

@Suite("Chat Markdown Formatter")
struct ChatMarkdownFormatterTests {

    @Test("Promotes obvious unfenced code runs into fenced markdown")
    func promotesUnfencedCodeRuns() {
        let rendered = ChatMarkdownFormatter.renderableContent(
            """
            Numba example:

            import numpy as np
            from numba import jit
            @jit(nopython=True)
            def fast_dot(x, y):
                return np.dot(x, y)

            **Example usage**
            xs = np.random.rand(1000)
            ys = np.random.rand(1000)
            result = fast_dot(xs, ys)
            summary = np.asarray(result)
            """
        )

        #expect(rendered.contains(
            """
            ```python
            import numpy as np
            from numba import jit
            @jit(nopython=True)
            def fast_dot(x, y):
                return np.dot(x, y)
            ```
            """
        ))
        #expect(rendered.contains("**Example usage**"))
        #expect(rendered.contains(
            """
            ```python
            xs = np.random.rand(1000)
            ys = np.random.rand(1000)
            result = fast_dot(xs, ys)
            summary = np.asarray(result)
            ```
            """
        ))
    }

    @Test("Leaves ordinary prose with soft line breaks alone")
    func leavesOrdinaryProseAlone() {
        let input = """
        This is a short explanation
        that should stay as prose
        even when it spans lines.
        """

        #expect(ChatMarkdownFormatter.renderableContent(input) == input)
    }

    @Test("Preserves existing fenced code blocks")
    func preservesExistingFences() {
        let input = """
        ```swift
        let greeting = "hello"
        print(greeting)
        ```
        """

        #expect(ChatMarkdownFormatter.renderableContent(input) == input)
    }

    @Test("Closes an unmatched fenced block for rendering")
    func closesUnmatchedFence() {
        let rendered = ChatMarkdownFormatter.renderableContent(
            """
            ```swift
            let greeting = "hello"
            """
        )

        #expect(rendered.hasSuffix("\n```"))
    }

    @Test("Artifact extraction sees promoted unfenced code")
    func artifactExtractionUsesNormalizedMarkdown() {
        let artifacts = ArtifactExtractor.extract(
            from:
            """
            from numba import njit
            import numpy as np

            @njit
            def add_one(xs):
                return xs + 1
                values = np.arange(4)
            """
        )

        #expect(artifacts.count == 1)
        #expect(artifacts.first?.language == "python")
    }
}
