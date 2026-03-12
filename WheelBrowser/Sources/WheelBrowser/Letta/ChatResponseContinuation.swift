import Foundation

enum ChatResponseContinuation {
    static let maxAttempts = 1

    static let prompt = """
    Continue your previous answer from exactly where it stopped.
    Do not repeat any text from the previous answer.
    Do not add an introduction, apology, or summary.
    Return only the continuation in markdown.
    """

    static func shouldRequestContinuation(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }

        let lastLine = trimmed
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .last
            .map(String.init) ?? trimmed
        let lastLineTrimmed = lastLine.trimmingCharacters(in: .whitespaces)

        if lastLineTrimmed.range(
            of: #"^(?:\d+\.\s+)?(?:\*\*|__|`|\*|_|[-+*]|>|\|)$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if trimmed.hasSuffix("**")
            || trimmed.hasSuffix("__")
            || trimmed.hasSuffix("`")
            || trimmed.hasSuffix("[")
            || trimmed.hasSuffix("(")
            || trimmed.hasSuffix("{") {
            return true
        }

        return hasUnbalancedFencedCodeBlock(in: trimmed)
    }

    static func merge(base: String, continuation: String) -> String {
        guard continuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return base
        }
        guard base.isEmpty == false else {
            return continuation
        }

        let maxOverlap = min(base.count, continuation.count, 200)
        guard maxOverlap > 0 else {
            return base + continuation
        }

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let baseStart = base.index(base.endIndex, offsetBy: -overlap)
            let continuationEnd = continuation.index(continuation.startIndex, offsetBy: overlap)
            if base[baseStart...] == continuation[..<continuationEnd] {
                return base + continuation[continuationEnd...]
            }
        }

        return base + continuation
    }

    private static func hasUnbalancedFencedCodeBlock(in text: String) -> Bool {
        let fenceCount = max(0, text.components(separatedBy: "```").count - 1)
        return fenceCount % 2 != 0
    }
}
