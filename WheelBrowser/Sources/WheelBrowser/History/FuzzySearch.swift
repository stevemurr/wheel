import Foundation

/// Result of a fuzzy match containing score and matched character positions
struct FuzzyMatch {
    let score: Int
    let matchedIndices: [Int]  // character offsets in the target string
}

/// Fuzzy search algorithm for matching user input against history entries
enum FuzzySearch {
    /// Calculate a fuzzy match score between query and target string
    /// Returns a score where higher is better, 0 means no match
    static func score(query: String, target: String) -> Int {
        match(query: query, target: target)?.score ?? 0
    }

    /// Calculate a fuzzy match with both score and matched character positions
    /// Returns nil if no match, otherwise a FuzzyMatch with score and indices
    static func match(query: String, target: String) -> FuzzyMatch? {
        guard !query.isEmpty else { return nil }
        guard !target.isEmpty else { return nil }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        // Quick check: if query is longer than target, no match possible
        guard queryLower.count <= targetLower.count else { return nil }

        // Exact match gets highest score
        if targetLower == queryLower {
            return FuzzyMatch(score: 1000, matchedIndices: Array(0..<targetLower.count))
        }

        // Contains match (substring)
        if let range = targetLower.range(of: queryLower) {
            let startOffset = targetLower.distance(from: targetLower.startIndex, to: range.lowerBound)
            let indices = Array(startOffset..<(startOffset + queryLower.count))

            // Bonus for matching at the start
            if startOffset == 0 {
                return FuzzyMatch(score: 800, matchedIndices: indices)
            }
            // Bonus for matching after common separators
            let separators = ["://", "/", ".", "-", "_", " "]
            for sep in separators {
                if targetLower.contains(sep + queryLower) {
                    return FuzzyMatch(score: 700, matchedIndices: indices)
                }
            }
            return FuzzyMatch(score: 600, matchedIndices: indices)
        }

        // Fuzzy character matching using String indices directly (avoids array allocation)
        var score = 0
        var queryIndex = queryLower.startIndex
        var targetIndex = targetLower.startIndex
        var consecutiveMatches = 0
        var matchCount = 0
        var lastMatchOffset: Int?
        var currentTargetOffset = 0
        var matchedIndices: [Int] = []

        while queryIndex < queryLower.endIndex && targetIndex < targetLower.endIndex {
            if queryLower[queryIndex] == targetLower[targetIndex] {
                matchCount += 1
                matchedIndices.append(currentTargetOffset)

                // Bonus for consecutive matches
                if let lastOffset = lastMatchOffset {
                    let distance = currentTargetOffset - lastOffset
                    if distance == 1 {
                        consecutiveMatches += 1
                        score += 10 * consecutiveMatches // Increasing bonus for consecutive matches
                    } else {
                        consecutiveMatches = 0
                        // Penalty for gaps, but less severe for small gaps
                        score -= min(distance - 1, 3)
                    }
                }

                // Bonus for matching at word boundaries
                if targetIndex == targetLower.startIndex {
                    score += 15
                } else {
                    let prevIndex = targetLower.index(before: targetIndex)
                    let prevChar = targetLower[prevIndex]
                    if !prevChar.isLetter && !prevChar.isNumber {
                        score += 10 // Word boundary bonus
                    }
                }

                lastMatchOffset = currentTargetOffset
                queryIndex = queryLower.index(after: queryIndex)
                score += 5 // Base score for each match
            }

            targetIndex = targetLower.index(after: targetIndex)
            currentTargetOffset += 1
        }

        // All query characters must be matched
        guard queryIndex == queryLower.endIndex else {
            return nil
        }

        // Bonus based on match ratio
        let matchRatio = Double(matchCount) / Double(targetLower.count)
        score += Int(matchRatio * 50)

        return FuzzyMatch(score: max(score, 1), matchedIndices: matchedIndices)
    }

    /// Score both title and URL, returning the best match result with indices for both
    struct BestMatchResult {
        let bestScore: Int
        let titleMatch: FuzzyMatch?
        let urlMatch: FuzzyMatch?
    }

    static func bestMatch(query: String, title: String, url: String) -> BestMatchResult? {
        let titleMatch = match(query: query, target: title)
        let urlMatch = match(query: query, target: url)
        let titleScore = titleMatch?.score ?? 0
        let urlScore = urlMatch?.score ?? 0
        let best = max(titleScore, urlScore)
        guard best > 0 else { return nil }
        return BestMatchResult(bestScore: best, titleMatch: titleMatch, urlMatch: urlMatch)
    }

    /// Filter and rank items based on fuzzy matching
    static func filter<T>(
        items: [T],
        query: String,
        keyPath: KeyPath<T, String>,
        limit: Int = 10
    ) -> [T] {
        guard !query.isEmpty else {
            return Array(items.prefix(limit))
        }

        let scored = items.compactMap { item -> (item: T, score: Int)? in
            let target = item[keyPath: keyPath]
            let matchScore = score(query: query, target: target)
            guard matchScore > 0 else { return nil }
            return (item, matchScore)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.item }
    }
}
