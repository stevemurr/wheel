import SwiftUI

/// Lightweight regex-based syntax highlighter for common languages.
/// Maps token types to semantic macOS colors.
enum SyntaxHighlighter {

    enum TokenType {
        case keyword
        case string
        case comment
        case number
        case type
        case plain
    }

    struct Token {
        let text: String
        let type: TokenType
    }

    /// Tokenize source code for the given language
    static func tokenize(_ source: String, language: String?) -> [Token] {
        guard let lang = language?.lowercased(), !source.isEmpty else {
            return [Token(text: source, type: .plain)]
        }

        let patterns = languagePatterns(for: lang)
        guard !patterns.isEmpty else {
            return [Token(text: source, type: .plain)]
        }

        return applyPatterns(source: source, patterns: patterns)
    }

    /// Get color for a token type
    static func color(for tokenType: TokenType) -> Color {
        switch tokenType {
        case .keyword:
            return Color(nsColor: .systemPink)
        case .string:
            return Color(nsColor: .systemGreen)
        case .comment:
            return .secondary.opacity(0.7)
        case .number:
            return Color(nsColor: .systemOrange)
        case .type:
            return Color(nsColor: .systemTeal)
        case .plain:
            return .primary
        }
    }

    /// Build an AttributedString with syntax highlighting
    static func highlight(_ source: String, language: String?) -> AttributedString {
        let tokens = tokenize(source, language: language)
        var result = AttributedString()

        for token in tokens {
            var attr = AttributedString(token.text)
            attr.foregroundColor = color(for: token.type)
            result.append(attr)
        }

        return result
    }

    // MARK: - Language Patterns

    private struct Pattern {
        let regex: NSRegularExpression
        let type: TokenType
    }

    private static func languagePatterns(for language: String) -> [Pattern] {
        switch language {
        case "swift":
            return swiftPatterns
        case "python", "py":
            return pythonPatterns
        case "javascript", "js", "typescript", "ts", "jsx", "tsx":
            return jsPatterns
        case "json":
            return jsonPatterns
        case "html", "xml":
            return htmlPatterns
        case "css":
            return cssPatterns
        case "go":
            return goPatterns
        case "rust", "rs":
            return rustPatterns
        default:
            return genericPatterns
        }
    }

    private static let swiftPatterns: [Pattern] = buildPatterns(
        keywords: "func|let|var|class|struct|enum|protocol|import|return|if|else|guard|switch|case|for|while|in|do|try|catch|throw|throws|async|await|public|private|internal|fileprivate|open|static|override|self|Self|nil|true|false|where|typealias|extension|init|deinit|subscript|some|any|weak|unowned|lazy|mutating|nonmutating|final|inout|break|continue|default|defer|fallthrough|repeat|associatedtype|convenience|dynamic|indirect|operator|optional|precedencegroup|required|willSet|didSet|get|set|is|as",
        types: "String|Int|Double|Float|Bool|Array|Dictionary|Set|Optional|Result|UUID|Date|URL|Data|Error|Void|Any|AnyObject|Never|Character|Substring|ClosedRange|Range",
        stringPattern: #"\"\"\"[\s\S]*?\"\"\"|\"(?:[^\"\\]|\\.)*\""#,
        commentPattern: #"//.*$|/\*[\s\S]*?\*/"#
    )

    private static let pythonPatterns: [Pattern] = buildPatterns(
        keywords: "def|class|import|from|return|if|elif|else|for|while|in|try|except|finally|raise|with|as|pass|break|continue|yield|lambda|and|or|not|is|True|False|None|self|async|await|global|nonlocal|del|assert",
        types: "int|str|float|bool|list|dict|tuple|set|bytes|type|object|Exception",
        stringPattern: #"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|f\"(?:[^\"\\]|\\.)*\"|\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"#,
        commentPattern: "#.*$"
    )

    private static let jsPatterns: [Pattern] = buildPatterns(
        keywords: "function|const|let|var|class|return|if|else|for|while|do|switch|case|break|continue|try|catch|throw|finally|new|delete|typeof|instanceof|in|of|import|export|default|from|async|await|yield|this|super|extends|static|get|set|true|false|null|undefined|void|interface|type|enum",
        types: "Array|Object|String|Number|Boolean|Promise|Map|Set|Date|RegExp|Error|Symbol|BigInt",
        stringPattern: #"`(?:[^`\\]|\\.)*`|\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"#,
        commentPattern: #"//.*$|/\*[\s\S]*?\*/"#
    )

    private static let jsonPatterns: [Pattern] = {
        var patterns: [Pattern] = []
        // Keys (strings followed by colon)
        if let re = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\"(?=\s*:)"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .type))
        }
        // String values
        if let re = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\""#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .string))
        }
        // Numbers
        if let re = try? NSRegularExpression(pattern: #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .number))
        }
        // Booleans / null
        if let re = try? NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .keyword))
        }
        return patterns
    }()

    private static let htmlPatterns: [Pattern] = {
        var patterns: [Pattern] = []
        // Tags
        if let re = try? NSRegularExpression(pattern: #"</?[a-zA-Z][a-zA-Z0-9]*"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .keyword))
        }
        // Attributes
        if let re = try? NSRegularExpression(pattern: #"\b[a-zA-Z-]+(?=\s*=)"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .type))
        }
        // Strings
        if let re = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .string))
        }
        // Comments
        if let re = try? NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .comment))
        }
        return patterns
    }()

    private static let cssPatterns: [Pattern] = buildPatterns(
        keywords: "import|media|keyframes|font-face|supports|charset",
        types: "px|em|rem|vh|vw|%|deg|s|ms",
        stringPattern: #"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"#,
        commentPattern: #"/\*[\s\S]*?\*/"#
    )

    private static let goPatterns: [Pattern] = buildPatterns(
        keywords: "func|var|const|type|struct|interface|map|chan|go|select|case|default|if|else|for|range|switch|return|break|continue|defer|package|import|nil|true|false|fallthrough",
        types: "string|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|bool|byte|rune|error|any",
        stringPattern: #"`[^`]*`|\"(?:[^\"\\]|\\.)*\""#,
        commentPattern: #"//.*$|/\*[\s\S]*?\*/"#
    )

    private static let rustPatterns: [Pattern] = buildPatterns(
        keywords: "fn|let|mut|const|struct|enum|impl|trait|pub|use|mod|crate|self|Self|super|return|if|else|match|for|while|loop|in|as|break|continue|move|async|await|unsafe|where|type|static|ref|true|false|None|Some|Ok|Err",
        types: "String|str|i8|i16|i32|i64|i128|u8|u16|u32|u64|u128|f32|f64|bool|char|usize|isize|Vec|Box|Option|Result|HashMap|HashSet",
        stringPattern: #"\"(?:[^\"\\]|\\.)*\""#,
        commentPattern: #"//.*$|/\*[\s\S]*?\*/"#
    )

    private static let genericPatterns: [Pattern] = {
        var patterns: [Pattern] = []
        // Comments
        if let re = try? NSRegularExpression(pattern: #"//.*$|#.*$|/\*[\s\S]*?\*/"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .comment))
        }
        // Strings
        if let re = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .string))
        }
        // Numbers
        if let re = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .number))
        }
        return patterns
    }()

    // MARK: - Pattern Builder

    private static func buildPatterns(
        keywords: String,
        types: String,
        stringPattern: String,
        commentPattern: String
    ) -> [Pattern] {
        var patterns: [Pattern] = []

        // Comments (highest priority)
        if let re = try? NSRegularExpression(pattern: commentPattern, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .comment))
        }
        // Strings
        if let re = try? NSRegularExpression(pattern: stringPattern, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .string))
        }
        // Types
        if let re = try? NSRegularExpression(pattern: #"\b(?:\#(types))\b"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .type))
        }
        // Keywords
        if let re = try? NSRegularExpression(pattern: #"\b(?:\#(keywords))\b"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .keyword))
        }
        // Numbers
        if let re = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, options: .anchorsMatchLines) {
            patterns.append(Pattern(regex: re, type: .number))
        }

        return patterns
    }

    // MARK: - Pattern Application

    private static func applyPatterns(source: String, patterns: [Pattern]) -> [Token] {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        // Collect all matches with their token types, sorted by location
        var allMatches: [(range: NSRange, type: TokenType)] = []

        for pattern in patterns {
            let matches = pattern.regex.matches(in: source, range: fullRange)
            for match in matches {
                allMatches.append((range: match.range, type: pattern.type))
            }
        }

        // Sort by location, then by length (longer matches first for overlaps)
        allMatches.sort { a, b in
            if a.range.location != b.range.location {
                return a.range.location < b.range.location
            }
            return a.range.length > b.range.length
        }

        // Build tokens, skipping overlapping matches
        var tokens: [Token] = []
        var currentIndex = 0

        for match in allMatches {
            let matchStart = match.range.location
            let matchEnd = matchStart + match.range.length

            // Skip if this match overlaps with already processed content
            guard matchStart >= currentIndex else { continue }

            // Add plain text before this match
            if matchStart > currentIndex {
                let plainRange = NSRange(location: currentIndex, length: matchStart - currentIndex)
                tokens.append(Token(text: nsSource.substring(with: plainRange), type: .plain))
            }

            // Add the matched token
            tokens.append(Token(text: nsSource.substring(with: match.range), type: match.type))
            currentIndex = matchEnd
        }

        // Add remaining plain text
        if currentIndex < nsSource.length {
            let remainingRange = NSRange(location: currentIndex, length: nsSource.length - currentIndex)
            tokens.append(Token(text: nsSource.substring(with: remainingRange), type: .plain))
        }

        return tokens
    }

    /// Detect language from common aliases
    static func normalizeLanguage(_ language: String?) -> String? {
        guard let lang = language?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        switch lang {
        case "swift": return "swift"
        case "python", "py": return "python"
        case "javascript", "js": return "javascript"
        case "typescript", "ts": return "typescript"
        case "jsx": return "javascript"
        case "tsx": return "typescript"
        case "json": return "json"
        case "html", "htm": return "html"
        case "xml": return "html"
        case "css", "scss", "sass": return "css"
        case "go", "golang": return "go"
        case "rust", "rs": return "rust"
        case "bash", "sh", "zsh", "shell": return "bash"
        case "sql": return "sql"
        case "ruby", "rb": return "ruby"
        case "java": return "java"
        case "kotlin", "kt": return "kotlin"
        case "c", "cpp", "c++", "cc", "cxx", "h", "hpp": return "c"
        case "csharp", "cs", "c#": return "csharp"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "markdown", "md": return "markdown"
        default: return lang
        }
    }
}
