import Foundation

/// Scans assistant message content for fenced code blocks and creates ChatArtifact instances.
enum ArtifactExtractor {

    /// Extract artifacts from markdown content containing fenced code blocks.
    /// Only creates artifacts for blocks of meaningful size (>3 lines).
    static func extract(from content: String) -> [ChatArtifact] {
        let pattern = #"```(\w*)\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var artifacts: [ChatArtifact] = []

        for match in matches {
            // Extract language
            let langRange = match.range(at: 1)
            let language = langRange.length > 0 ? nsContent.substring(with: langRange) : nil

            // Extract code content
            let codeRange = match.range(at: 2)
            guard codeRange.length > 0 else { continue }
            let code = nsContent.substring(with: codeRange).trimmingCharacters(in: .newlines)

            // Only create artifacts for meaningful code blocks (>3 lines)
            let lineCount = code.components(separatedBy: .newlines).count
            guard lineCount > 3 else { continue }

            // Determine artifact type
            let type = artifactType(for: language)

            // Generate title from content
            let title = generateTitle(from: code, language: language)

            artifacts.append(ChatArtifact(
                title: title,
                language: SyntaxHighlighter.normalizeLanguage(language),
                content: code,
                type: type
            ))
        }

        return artifacts
    }

    /// Determine artifact type from language identifier
    private static func artifactType(for language: String?) -> ChatArtifact.ArtifactType {
        guard let lang = language?.lowercased() else { return .plainText }
        switch lang {
        case "markdown", "md":
            return .markdown
        case "html", "htm", "xml":
            return .html
        case "json":
            return .json
        default:
            return .code
        }
    }

    /// Generate a title from the first meaningful line of code
    private static func generateTitle(from code: String, language: String?) -> String {
        let lines = code.components(separatedBy: .newlines)

        // Try to find a function/class/struct definition
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Function definitions
            if trimmed.hasPrefix("func ") || trimmed.hasPrefix("def ") || trimmed.hasPrefix("function ") {
                return extractIdentifier(from: trimmed)
            }

            // Class/struct/enum definitions
            if trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("enum ") ||
               trimmed.hasPrefix("protocol ") || trimmed.hasPrefix("interface ") {
                return extractIdentifier(from: trimmed)
            }

            // First comment
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
                let comment = trimmed
                    .replacingOccurrences(of: "^[/#*\\s]+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty && comment.count < 50 {
                    return comment
                }
            }
        }

        // Fallback: use language + line count
        let langLabel = SyntaxHighlighter.normalizeLanguage(language) ?? "Code"
        return "\(langLabel.capitalized) (\(lines.count) lines)"
    }

    /// Extract the identifier name from a definition line
    private static func extractIdentifier(from line: String) -> String {
        let cleaned = line
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet(charactersIn: "({<:"))
            .first ?? line

        if cleaned.count > 50 {
            return String(cleaned.prefix(47)) + "..."
        }
        return cleaned
    }
}
