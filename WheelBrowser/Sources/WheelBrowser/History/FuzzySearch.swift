import Foundation

/// Fuzzy search algorithm for matching user input against history entries
enum FuzzySearch {
    /// Calculate a fuzzy match score between query and target string
    /// Returns a score where higher is better, 0 means no match
    static func score(query: String, target: String) -> Int {
        guard !query.isEmpty else { return 0 }
        guard !target.isEmpty else { return 0 }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        // Quick check: if query is longer than target, no match possible
        guard queryLower.count <= targetLower.count else { return 0 }

        // Exact match gets highest score
        if targetLower == queryLower {
            return 1000
        }

        // Contains match (substring)
        if targetLower.contains(queryLower) {
            // Bonus for matching at the start
            if targetLower.hasPrefix(queryLower) {
                return 800
            }
            // Bonus for matching after common separators
            let separators = ["://", "/", ".", "-", "_", " "]
            for sep in separators {
                if targetLower.contains(sep + queryLower) {
                    return 700
                }
            }
            return 600
        }

        // Fuzzy character matching
        var score = 0
        var queryIndex = queryLower.startIndex
        var targetIndex = targetLower.startIndex
        var consecutiveMatches = 0
        var matchCount = 0
        var lastMatchIndex: String.Index?

        while queryIndex < queryLower.endIndex && targetIndex < targetLower.endIndex {
            let queryChar = queryLower[queryIndex]
            let targetChar = targetLower[targetIndex]

            if queryChar == targetChar {
                matchCount += 1

                // Bonus for consecutive matches
                if let lastIdx = lastMatchIndex {
                    let distance = targetLower.distance(from: lastIdx, to: targetIndex)
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

                lastMatchIndex = targetIndex
                queryIndex = queryLower.index(after: queryIndex)
                score += 5 // Base score for each match
            }

            targetIndex = targetLower.index(after: targetIndex)
        }

        // All query characters must be matched
        guard queryIndex == queryLower.endIndex else {
            return 0
        }

        // Bonus based on match ratio
        let matchRatio = Double(matchCount) / Double(targetLower.count)
        score += Int(matchRatio * 50)

        return max(score, 1) // Ensure minimum score of 1 if we matched
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
