import Foundation

/// Normalizes chat markdown for display without mutating the stored message text.
/// The main fix-up promotes obvious unfenced multi-line code into fenced code blocks
/// so Markdown rendering preserves line breaks and syntax highlighting.
enum ChatMarkdownFormatter {

    static func renderableContent(_ content: String, closeUnbalancedFence: Bool = true) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.isEmpty == false else {
            return normalized
        }

        return promoteUnfencedCodeBlocks(in: normalized, closeUnbalancedFence: closeUnbalancedFence)
    }

    private static func promoteUnfencedCodeBlocks(
        in markdown: String,
        closeUnbalancedFence: Bool
    ) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var result: [String] = []
        var outsideFence: [String] = []
        var fenceBuffer: [String] = []
        var isInsideFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInsideFence {
                    fenceBuffer.append(line)
                    result.append(contentsOf: fenceBuffer)
                    fenceBuffer.removeAll(keepingCapacity: true)
                    isInsideFence = false
                } else {
                    result.append(contentsOf: promoteOutsideFenceContent(outsideFence))
                    outsideFence.removeAll(keepingCapacity: true)
                    fenceBuffer = [line]
                    isInsideFence = true
                }
                continue
            }

            if isInsideFence {
                fenceBuffer.append(line)
            } else {
                outsideFence.append(line)
            }
        }

        result.append(contentsOf: promoteOutsideFenceContent(outsideFence))

        if fenceBuffer.isEmpty == false {
            result.append(contentsOf: fenceBuffer)
            if closeUnbalancedFence {
                result.append("```")
            }
        }

        return result.joined(separator: "\n")
    }

    private static func promoteOutsideFenceContent(_ lines: [String]) -> [String] {
        guard lines.isEmpty == false else {
            return []
        }

        var result: [String] = []
        var index = 0
        var lastInferredLanguage: String?

        while index < lines.count {
            if shouldStartCodeCluster(at: index, in: lines) {
                let cluster = consumeCodeCluster(startingAt: index, in: lines)
                let inferredLanguage = inferLanguage(from: cluster.lines) ?? lastInferredLanguage
                let fenced = fencedBlock(
                    from: cluster.lines,
                    language: inferredLanguage
                )
                if let inferredLanguage {
                    lastInferredLanguage = inferredLanguage
                }
                result.append(contentsOf: fenced)
                index = cluster.nextIndex
                continue
            }

            result.append(lines[index])
            index += 1
        }

        return result
    }

    private static func fencedBlock(from lines: [String], language: String?) -> [String] {
        var trimmedLines = lines
        var trailingBlankLines: [String] = []

        while let last = trimmedLines.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty {
            trailingBlankLines.insert(last, at: 0)
            trimmedLines.removeLast()
        }

        guard trimmedLines.isEmpty == false else {
            return lines
        }

        let fenceHeader = language.map { "```\($0)" } ?? "```"
        return [fenceHeader] + trimmedLines + ["```"] + trailingBlankLines
    }

    private static func shouldStartCodeCluster(at index: Int, in lines: [String]) -> Bool {
        guard isStrongCodeLine(lines[index]) else {
            return false
        }

        var strongMatches = 0
        var probe = index

        while probe < lines.count, probe <= index + 2 {
            let trimmed = lines[probe].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                probe += 1
                continue
            }

            if isStrongCodeLine(lines[probe]) {
                strongMatches += 1
                if strongMatches >= 2 {
                    return true
                }
                probe += 1
                continue
            }

            return false
        }

        return false
    }

    private static func consumeCodeCluster(startingAt index: Int, in lines: [String]) -> (lines: [String], nextIndex: Int) {
        var collected: [String] = []
        var cursor = index

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                collected.append(line)
                cursor += 1
                continue
            }

            if isCodeContinuationLine(line) {
                collected.append(line)
                cursor += 1
                continue
            }

            break
        }

        return (collected, cursor)
    }

    private static func isCodeContinuationLine(_ line: String) -> Bool {
        isStrongCodeLine(line) || isCommentLine(line)
    }

    private static func isStrongCodeLine(_ line: String) -> Bool {
        codeSignalScore(for: line) >= 2
    }

    private static func isCommentLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else {
            return false
        }

        if looksLikeMarkdownBlockSyntax(trimmed) {
            return false
        }

        return trimmed.hasPrefix("//")
            || trimmed.hasPrefix("/*")
            || trimmed.hasPrefix("* ")
            || trimmed.hasPrefix("-- ")
            || trimmed.hasPrefix("#!")
    }

    private static func codeSignalScore(for line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else {
            return 0
        }

        if looksLikeMarkdownBlockSyntax(trimmed) {
            return 0
        }

        var score = 0
        let leadingSpaces = line.prefix { $0 == " " }.count

        if leadingSpaces >= 4 || line.hasPrefix("\t") {
            score += 1
        }

        if hasCodePrefix(trimmed) {
            score += 2
        }

        if trimmed == "{" || trimmed == "}" || trimmed == "[" || trimmed == "]" ||
            trimmed == "(" || trimmed == ")" {
            score += 2
        }

        if trimmed.hasPrefix("</") || (trimmed.hasPrefix("<") && trimmed.hasSuffix(">")) {
            score += 2
        }

        if trimmed.contains(" = ") || trimmed.contains(":=") || trimmed.contains("=>") ||
            trimmed.contains("->") || trimmed.contains("::") {
            score += 1
        }

        if trimmed.contains("(") && trimmed.contains(")") {
            score += 1
        }

        if trimmed.contains("[") && trimmed.contains("]") {
            score += 1
        }

        if trimmed.hasSuffix(":") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}") ||
            trimmed.hasSuffix(";") {
            score += 1
        }

        if trimmed.contains(".") && (trimmed.contains("(") || trimmed.contains("=")) {
            score += 1
        }

        return score
    }

    private static func hasCodePrefix(_ trimmed: String) -> Bool {
        let lowercased = trimmed.lowercased()
        let prefixes = [
            "import ", "from ", "def ", "class ", "@", "return ", "if ", "elif ", "else:",
            "for ", "while ", "try:", "except", "with ", "pass", "break", "continue",
            "func ", "let ", "var ", "struct ", "enum ", "protocol ", "guard ", "switch ",
            "case ", "const ", "function ", "interface ", "type ", "export ", "package ",
            "use ", "fn ", "pub ", "$ ", ">>> ", "pip ", "python ", "python3 ", "npm ",
            "pnpm ", "yarn ", "swift ", "git ", "curl ", "brew ", "cargo ", "go ",
            "select ", "insert ", "update ", "delete ", "create ", "alter ", "with "
        ]
        return prefixes.contains { lowercased.hasPrefix($0) }
    }

    private static func looksLikeMarkdownBlockSyntax(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("```") || trimmed.hasPrefix(">") || trimmed.hasPrefix("|") {
            return true
        }

        if trimmed.hasPrefix("# ") || trimmed.hasPrefix("##") {
            return true
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }

        return isNumberedMarkdownListItem(trimmed)
    }

    private static func isNumberedMarkdownListItem(_ trimmed: String) -> Bool {
        var digits = 0
        for character in trimmed {
            if character.isNumber {
                digits += 1
                continue
            }
            if character == ".", digits > 0 {
                return trimmed.dropFirst(digits + 1).first == " "
            }
            return false
        }
        return false
    }

    private static func inferLanguage(from lines: [String]) -> String? {
        let nonEmptyLines = lines.map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter {
            $0.isEmpty == false
        }

        guard nonEmptyLines.isEmpty == false else {
            return nil
        }

        var scores: [String: Int] = [:]

        for line in nonEmptyLines {
            let lowercased = line.lowercased()

            if lowercased.hasPrefix("from ") || lowercased.hasPrefix("def ") || line.hasPrefix("@") ||
                lowercased.hasPrefix("elif ") || lowercased.hasPrefix("except") ||
                lowercased == "else:" || lowercased == "try:" {
                scores["python", default: 0] += 2
            }

            if lowercased.hasPrefix("let ") || lowercased.hasPrefix("guard ") ||
                lowercased.hasPrefix("func ") || lowercased.hasPrefix("struct ") ||
                lowercased.hasPrefix("protocol ") {
                scores["swift", default: 0] += 2
            }

            if lowercased.hasPrefix("const ") || lowercased.hasPrefix("function ") ||
                lowercased.contains("=>") || lowercased.hasPrefix("export ") {
                scores["javascript", default: 0] += 2
            }

            if line.hasPrefix("$ ") || lowercased.hasPrefix("pip ") || lowercased.hasPrefix("python ") ||
                lowercased.hasPrefix("python3 ") || lowercased.hasPrefix("npm ") ||
                lowercased.hasPrefix("pnpm ") || lowercased.hasPrefix("yarn ") ||
                lowercased.hasPrefix("git ") || lowercased.hasPrefix("curl ") ||
                lowercased.hasPrefix("brew ") {
                scores["bash", default: 0] += 2
            }

            if lowercased.hasPrefix("select ") || lowercased.hasPrefix("insert ") ||
                lowercased.hasPrefix("update ") || lowercased.hasPrefix("delete ") ||
                lowercased.hasPrefix("create ") || lowercased.hasPrefix("alter ") ||
                lowercased.hasPrefix("with ") {
                scores["sql", default: 0] += 2
            }

            if line.hasPrefix("</") || (line.hasPrefix("<") && line.hasSuffix(">")) {
                scores["html", default: 0] += 2
            }

            if lowercased.hasPrefix("\"") && lowercased.contains("\":") {
                scores["json", default: 0] += 1
            }
        }

        guard let best = scores.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return nil
        }

        return best.value >= 2 ? best.key : nil
    }
}
