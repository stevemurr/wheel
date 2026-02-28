import Foundation

/// Detects complete markdown structures that represent safe flush points
/// for streaming content. This reduces UI updates while ensuring meaningful
/// visual progress during LLM streaming.
///
/// The flusher recognizes:
/// - Paragraph breaks (`\n\n`)
/// - Code block boundaries (` ``` `)
/// - LaTeX block boundaries (`$$`)
/// - Sentence endings (`. `, `! `, `? `)
/// - Completed list items, headings, blockquotes
/// - Table row boundaries (`|\n`)
/// - Large buffer fallback (>200 chars at a newline)
struct MarkdownBufferFlusher {

    /// Determines whether the pending buffer content should be flushed to the UI.
    ///
    /// - Parameter buffer: The accumulated text that has not yet been flushed.
    /// - Returns: `true` if the buffer ends at a natural markdown boundary.
    func shouldFlush(_ buffer: String) -> Bool {
        guard !buffer.isEmpty else { return false }

        // Paragraph break - most common flush point
        if buffer.hasSuffix("\n\n") {
            return true
        }

        // Code block boundaries
        if buffer.hasSuffix("```\n") || buffer.hasSuffix("```") {
            return true
        }

        // LaTeX block boundaries
        if buffer.hasSuffix("$$\n") || buffer.hasSuffix("$$") {
            return true
        }

        // End of sentence followed by space (natural reading break)
        if buffer.count >= 2 {
            let lastTwo = String(buffer.suffix(2))
            if lastTwo == ". " || lastTwo == "! " || lastTwo == "? " {
                return true
            }
        }

        // List item complete (newline after list content)
        if buffer.contains("\n") {
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if let lastLine = lines.last, lastLine.isEmpty {
                // Previous line was complete
                if lines.count >= 2 {
                    let prevLine = String(lines[lines.count - 2])
                    // Check if it was a list item or heading
                    let trimmed = prevLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                       trimmed.hasPrefix("# ") || trimmed.hasPrefix("> ") ||
                       trimmed.first?.isNumber == true && trimmed.contains(". ") {
                        return true
                    }
                }
            }
        }

        // Heading complete
        if buffer.hasSuffix("\n") && buffer.contains("#") {
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                let prevLine = String(lines[lines.count - 2])
                if prevLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    return true
                }
            }
        }

        // Table row complete
        if buffer.hasSuffix("|\n") {
            return true
        }

        // Fallback: flush on any newline if buffer is getting large
        if buffer.count > 200 && buffer.hasSuffix("\n") {
            return true
        }

        return false
    }
}
