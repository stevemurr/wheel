import Testing
@testable import WheelBrowser

@Suite("TextChunker Tests")
struct TextChunkerTests {

    // MARK: - Basic chunking

    @Test("Empty text returns empty array")
    func emptyText() {
        let chunks = TextChunker.chunk(text: "")
        #expect(chunks.isEmpty)
    }

    @Test("Whitespace-only text returns empty array")
    func whitespaceOnly() {
        let chunks = TextChunker.chunk(text: "   \n\n  \n  ")
        #expect(chunks.isEmpty)
    }

    @Test("Short text below min produces single chunk")
    func shortText() {
        let text = "This is a short paragraph that should not be split."
        let chunks = TextChunker.chunk(text: text)
        #expect(chunks.count == 1)
        #expect(chunks[0].content == text)
        #expect(chunks[0].sectionHierarchy.isEmpty)
        #expect(chunks[0].positionInDoc == 0.0)
    }

    @Test("Two paragraphs below min get merged")
    func twoShortParagraphsMerged() {
        let text = "First paragraph here.\n\nSecond paragraph here."
        let chunks = TextChunker.chunk(text: text)
        #expect(chunks.count == 1)
        #expect(chunks[0].content.contains("First paragraph"))
        #expect(chunks[0].content.contains("Second paragraph"))
        #expect(chunks[0].content.contains("\n\n"))
    }

    @Test("Two large paragraphs produce separate chunks")
    func twoLargeParagraphs() {
        // Each paragraph must exceed maxChunkChars/2 so combined > maxChunkChars (2000)
        let para1 = String(repeating: "Word ", count: 250) // ~1250 chars
        let para2 = String(repeating: "Text ", count: 250)
        let text = para1.trimmingCharacters(in: .whitespaces) + "\n\n" + para2.trimmingCharacters(in: .whitespaces)
        let chunks = TextChunker.chunk(text: text)
        #expect(chunks.count >= 2)
    }

    @Test("Very long paragraph gets split at sentence boundaries")
    func longParagraphSentenceSplit() {
        // Create a long paragraph with many sentences
        let sentence = "This is a test sentence that has some decent length to it. "
        let para = String(repeating: sentence, count: 50) // ~3000 chars
        let chunks = TextChunker.chunk(text: para)
        #expect(chunks.count >= 2)
        for chunk in chunks {
            // Each chunk should not exceed max (with some tolerance for overlap)
            // Overlap adds at most one sentence
            #expect(chunk.content.count <= TextChunker.maxChunkChars + 200)
        }
    }

    // MARK: - Heading detection

    @Test("Markdown headings are detected")
    func markdownHeadings() {
        #expect(TextChunker.isHeadingLine("# Introduction"))
        #expect(TextChunker.isHeadingLine("## Methods"))
        #expect(TextChunker.isHeadingLine("### Results and Discussion"))
    }

    @Test("All-caps headings are detected")
    func allCapsHeadings() {
        #expect(TextChunker.isHeadingLine("INTRODUCTION"))
        #expect(TextChunker.isHeadingLine("METHODS AND MATERIALS"))
    }

    @Test("Title case headings are detected")
    func titleCaseHeadings() {
        #expect(TextChunker.isHeadingLine("Introduction and Background"))
        #expect(TextChunker.isHeadingLine("The Quick Brown Fox"))
    }

    @Test("Regular sentences are not headings")
    func regularSentencesNotHeadings() {
        #expect(!TextChunker.isHeadingLine("This is a regular sentence with lowercase words."))
        #expect(!TextChunker.isHeadingLine("the quick brown fox jumps over the lazy dog."))
    }

    @Test("Long lines are not headings")
    func longLinesNotHeadings() {
        let longLine = String(repeating: "Word ", count: 20) // ~100 chars
        #expect(!TextChunker.isHeadingLine(longLine))
    }

    @Test("Empty line is not a heading")
    func emptyLineNotHeading() {
        #expect(!TextChunker.isHeadingLine(""))
        #expect(!TextChunker.isHeadingLine("   "))
    }

    // MARK: - Section hierarchy

    @Test("Headings create section hierarchy")
    func sectionHierarchy() {
        let text = """
        # Introduction

        This is the introduction paragraph with enough content to form a chunk on its own. \
        Let us add more text here to ensure we have sufficient characters for the chunker \
        to consider this a meaningful chunk. We need at least a few hundred characters to \
        meet the minimum chunk size requirement. Adding more sentences to fill the space \
        and ensure this paragraph is substantial enough for testing. The introduction \
        covers the background and motivation for our research.

        ## Methods

        These are the methods used in our research study. We describe the experimental \
        design, data collection procedures, and analysis techniques. The methodology \
        section is crucial for reproducibility and allows other researchers to verify \
        our findings. We employed both quantitative and qualitative approaches to \
        ensure comprehensive coverage of the research questions. Additional details \
        about specific protocols and instruments are provided below.
        """
        let chunks = TextChunker.chunk(text: text)
        #expect(chunks.count >= 1)

        // First chunk should have "Introduction" in hierarchy
        let introChunks = chunks.filter { $0.sectionHierarchy.contains("Introduction") }
        #expect(!introChunks.isEmpty)

        // Methods chunk should have "Methods" in hierarchy
        let methodChunks = chunks.filter { $0.sectionHierarchy.contains("Methods") }
        #expect(!methodChunks.isEmpty)
    }

    // MARK: - Position tracking

    @Test("Position in doc increases across chunks")
    func positionIncreases() {
        let sentence = "This is a moderately long sentence used for testing purposes. "
        let text = String(repeating: sentence, count: 80) // ~5000 chars, should produce multiple chunks
        let chunks = TextChunker.chunk(text: text)
        guard chunks.count >= 2 else { return }

        for i in 1..<chunks.count {
            #expect(chunks[i].positionInDoc >= chunks[i - 1].positionInDoc)
        }
    }

    @Test("charRange is within document bounds")
    func charRangeWithinBounds() {
        let text = "Hello world. This is a test.\n\nAnother paragraph here with more content."
        let chunks = TextChunker.chunk(text: text)
        for chunk in chunks {
            #expect(chunk.charRange.lowerBound >= 0)
            #expect(chunk.charRange.upperBound <= text.count)
        }
    }

    // MARK: - Sentence overlap

    @Test("Second chunk starts with overlap from first")
    func sentenceOverlap() {
        // Create text that will produce exactly 2 chunks
        let sent1 = "Alpha beta gamma delta. "
        let sent2 = "Epsilon zeta eta theta. "
        let block1 = String(repeating: sent1, count: 40) // ~960 chars
        let block2 = String(repeating: sent2, count: 40)
        let text = block1 + "\n\n" + block2
        let chunks = TextChunker.chunk(text: text)
        guard chunks.count >= 2 else { return }

        // Second chunk should start with last sentence of first chunk (overlap)
        let firstChunkSentences = TextChunker.splitSentences(chunks[0].content)
        if let lastSentOfFirst = firstChunkSentences.last {
            #expect(chunks[1].content.hasPrefix(lastSentOfFirst))
        }
    }

    // MARK: - Sentence splitting

    @Test("Basic sentence splitting")
    func basicSentenceSplitting() {
        let text = "Hello world. How are you? I am fine!"
        let sentences = TextChunker.splitSentences(text)
        #expect(sentences.count == 3)
        #expect(sentences[0] == "Hello world.")
        #expect(sentences[1] == "How are you?")
        #expect(sentences[2] == "I am fine!")
    }

    @Test("Single sentence without punctuation")
    func singleSentenceNoPunctuation() {
        let text = "Hello world"
        let sentences = TextChunker.splitSentences(text)
        #expect(sentences.count == 1)
        #expect(sentences[0] == "Hello world")
    }

    @Test("Empty string returns empty array")
    func emptySentenceSplitting() {
        let sentences = TextChunker.splitSentences("")
        #expect(sentences.isEmpty)
    }

    @Test("Sentence with trailing whitespace")
    func trailingWhitespace() {
        let sentences = TextChunker.splitSentences("  Hello.  World.  ")
        #expect(sentences.count == 2)
        #expect(sentences[0] == "Hello.")
        #expect(sentences[1] == "World.")
    }
}
