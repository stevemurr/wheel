import Foundation

enum PromptText {
    static func normalize(_ value: String, preservingSlash: Bool = false) -> String {
        let pattern = preservingSlash ? #"[^a-z0-9/ ]+"# : #"[^a-z0-9 ]+"#

        return value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt == word
            || prompt.hasPrefix("\(word) ")
            || prompt.hasSuffix(" \(word)")
            || prompt.contains(" \(word) ")
    }

    static func containsPhrase(_ phrase: String, in prompt: String) -> Bool {
        prompt.contains(phrase)
    }

    static func extractInteger(in pattern: String, from prompt: String) -> Int? {
        guard let match = prompt.range(of: pattern, options: .regularExpression),
              let value = Int(prompt[match]) else {
            return nil
        }
        return value
    }

    static func deduplicated<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
