import SwiftUI

/// Shared utility for building highlighted Text views with run-length grouping.
/// Groups contiguous highlighted/unhighlighted characters into runs, producing
/// one `Text` per run instead of one per character.
enum HighlightedTextBuilder {
    /// Build highlighted text from exact character indices (used by history/address bar suggestions)
    static func fromIndices(_ string: String, indices: [Int]) -> Text {
        guard !indices.isEmpty else {
            return Text(string).foregroundColor(.primary)
        }

        let indexSet = Set(indices)
        return buildRuns(string) { indexSet.contains($0) }
    }

    /// Build highlighted text from substring term matches (used by semantic search results)
    static func fromTerms(_ string: String, terms: [String]) -> Text {
        guard !terms.isEmpty else {
            return Text(string).foregroundColor(.primary)
        }

        let lowerString = string.lowercased()
        var highlighted = Set<Int>()

        for term in terms {
            let lowerTerm = term.lowercased()
            var searchStart = lowerString.startIndex
            while let range = lowerString.range(of: lowerTerm, range: searchStart..<lowerString.endIndex) {
                let startOffset = lowerString.distance(from: lowerString.startIndex, to: range.lowerBound)
                let endOffset = lowerString.distance(from: lowerString.startIndex, to: range.upperBound)
                for i in startOffset..<endOffset {
                    highlighted.insert(i)
                }
                searchStart = range.upperBound
            }
        }

        guard !highlighted.isEmpty else {
            return Text(string).foregroundColor(.primary)
        }

        return buildRuns(string) { highlighted.contains($0) }
    }

    /// Build Text by grouping contiguous characters with the same highlight state into runs.
    /// For a 28-char URL with 2 highlight groups: ~5 Text views instead of 28.
    private static func buildRuns(_ string: String, isHighlighted: (Int) -> Bool) -> Text {
        var runs: [Text] = []
        var currentRun = ""
        var currentIsHighlighted = false
        var isFirstRun = true

        for (i, char) in string.enumerated() {
            let charHighlighted = isHighlighted(i)

            if isFirstRun {
                currentIsHighlighted = charHighlighted
                isFirstRun = false
            }

            if charHighlighted != currentIsHighlighted {
                // Flush the current run
                runs.append(styledText(currentRun, highlighted: currentIsHighlighted))
                currentRun = ""
                currentIsHighlighted = charHighlighted
            }

            currentRun.append(char)
        }

        // Flush final run
        if !currentRun.isEmpty {
            runs.append(styledText(currentRun, highlighted: currentIsHighlighted))
        }

        guard let firstRun = runs.first else {
            return Text("")
        }

        return runs.dropFirst().reduce(firstRun) { combined, run in
            Text("\(combined)\(run)")
        }
    }

    private static func styledText(_ text: String, highlighted: Bool) -> Text {
        if highlighted {
            return Text(text).bold().foregroundColor(.primary)
        } else {
            return Text(text).foregroundColor(.secondary)
        }
    }
}
