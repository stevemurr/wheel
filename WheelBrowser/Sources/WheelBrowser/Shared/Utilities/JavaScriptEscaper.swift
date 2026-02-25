import Foundation

/// Utility for safely escaping text for JavaScript string injection
/// Handles all special characters that could break JS strings or cause injection issues
public enum JavaScriptEscaper {
    /// Escape a string for safe inclusion in a JavaScript string literal
    /// - Parameter text: The text to escape
    /// - Returns: Escaped text safe for JS string interpolation
    public static func escape(_ text: String) -> String {
        var result = text

        // Order matters - escape backslash first
        result = result.replacingOccurrences(of: "\\", with: "\\\\")

        // Escape quotes
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "'", with: "\\'")

        // Escape template literal characters
        result = result.replacingOccurrences(of: "`", with: "\\`")
        result = result.replacingOccurrences(of: "$", with: "\\$")

        // Escape control characters
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")

        // Strip null bytes (can't be safely escaped)
        result = result.replacingOccurrences(of: "\0", with: "")

        // Escape Unicode line/paragraph separators (can break JS strings)
        result = result.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        result = result.replacingOccurrences(of: "\u{2029}", with: "\\u2029")

        return result
    }
}
