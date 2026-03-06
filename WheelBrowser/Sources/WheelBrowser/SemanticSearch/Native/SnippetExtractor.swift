import Foundation

/// Extracts best-matching sentence snippets from chunk content
enum SnippetExtractor {

    /// Find the sentence in `content` with highest overlap with `queryTerms`.
    /// Returns the best-matching sentence, or nil if no query term appears in any sentence.
    static func extractSnippet(from content: String, queryTerms: [String]) -> String? {
        guard !content.isEmpty, !queryTerms.isEmpty else { return nil }

        let sentences = TextChunker.splitSentences(content)
        guard !sentences.isEmpty else { return nil }

        let lowercasedTerms = queryTerms.map { $0.lowercased() }

        var bestSentence: String?
        var bestScore = 0

        for sentence in sentences {
            let lowered = sentence.lowercased()
            var score = 0
            for term in lowercasedTerms {
                if lowered.contains(term) {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestSentence = sentence
            }
        }

        return bestSentence
    }
}
