import Foundation

/// A chunk of text extracted from a document
struct TextChunk: Sendable, Equatable {
    let content: String
    let sectionHierarchy: [String]
    let positionInDoc: Float  // 0.0–1.0
    let charRange: Range<Int>
}

/// Splits clean text into semantically meaningful chunks
enum TextChunker {
    // Target chunk sizes in characters (~4 chars per token)
    static let minChunkChars = 400   // ~100 tokens
    static let maxChunkChars = 2000  // ~500 tokens
    static let overlapSentences = 1  // last sentence overlap

    /// Split text into heading-aware, size-constrained chunks with sentence overlap.
    static func chunk(text: String) -> [TextChunk] {
        guard !text.isEmpty else { return [] }

        let totalChars = text.count
        let sections = splitIntoSections(text)
        var rawChunks: [(content: String, hierarchy: [String], startChar: Int)] = []

        for section in sections {
            let paragraphs = splitParagraphs(section.body)
            guard !paragraphs.isEmpty else { continue }

            var buffer = ""
            var bufferStart = section.bodyStartChar

            for para in paragraphs {
                let trimmed = para.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if buffer.isEmpty {
                    buffer = trimmed
                    bufferStart = para.startChar
                } else if buffer.count + 1 + trimmed.count <= maxChunkChars {
                    // Merge small paragraphs
                    buffer += "\n\n" + trimmed
                } else {
                    // Flush buffer
                    rawChunks.append((buffer, section.hierarchy, bufferStart))
                    buffer = trimmed
                    bufferStart = para.startChar
                }

                // Split oversized buffer at sentence boundaries
                while buffer.count > maxChunkChars {
                    let sentences = splitSentences(buffer)
                    if sentences.count <= 1 {
                        // Single sentence exceeds max; emit as-is
                        break
                    }
                    // Take as many sentences as fit
                    var take = ""
                    var sentCount = 0
                    for s in sentences {
                        let candidate = take.isEmpty ? s : take + " " + s
                        if candidate.count > maxChunkChars && !take.isEmpty {
                            break
                        }
                        take = candidate
                        sentCount += 1
                    }
                    rawChunks.append((take, section.hierarchy, bufferStart))
                    // Remainder
                    let remaining = sentences.dropFirst(sentCount).joined(separator: " ")
                    bufferStart += take.count + (buffer.count - take.count - remaining.count)
                    buffer = remaining
                }
            }

            // Flush remaining buffer
            if !buffer.isEmpty {
                rawChunks.append((buffer, section.hierarchy, bufferStart))
            }
        }

        // Merge undersized trailing chunks into predecessor within same section
        var merged: [(content: String, hierarchy: [String], startChar: Int)] = []
        for chunk in rawChunks {
            if let last = merged.last,
               last.hierarchy == chunk.hierarchy,
               last.content.count < minChunkChars,
               last.content.count + 2 + chunk.content.count <= maxChunkChars {
                let combined = last.content + "\n\n" + chunk.content
                merged[merged.count - 1] = (combined, last.hierarchy, last.startChar)
            } else {
                merged.append(chunk)
            }
        }

        // Build final chunks with overlap and position
        var result: [TextChunk] = []
        for (i, chunk) in merged.enumerated() {
            var content = chunk.content

            // Prepend last sentence of previous chunk as overlap
            if i > 0 && overlapSentences > 0 {
                let prevSentences = splitSentences(merged[i - 1].content)
                let overlap = prevSentences.suffix(overlapSentences).joined(separator: " ")
                if !overlap.isEmpty {
                    content = overlap + " " + content
                }
            }

            let position: Float = totalChars > 0
                ? Float(chunk.startChar) / Float(totalChars)
                : 0.0

            let endChar = min(chunk.startChar + chunk.content.count, totalChars)

            result.append(TextChunk(
                content: content,
                sectionHierarchy: chunk.hierarchy,
                positionInDoc: position,
                charRange: chunk.startChar..<endChar
            ))
        }

        return result
    }

    // MARK: - Sentence splitting

    /// Split text at sentence boundaries (period/question/exclamation followed by space or newline).
    static func splitSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Match sentence-ending punctuation followed by whitespace or end of string.
        // Handles abbreviations poorly but good enough for chunking.
        var sentences: [String] = []
        var current = ""

        let chars = Array(trimmed)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)

            if (c == "." || c == "?" || c == "!") {
                // Check if followed by whitespace or end of string
                let nextIdx = i + 1
                if nextIdx >= chars.count {
                    // End of string
                    let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { sentences.append(s) }
                    current = ""
                } else if chars[nextIdx].isWhitespace {
                    // Check it's not an abbreviation like "Dr. " or "U.S. " by looking at length of current word
                    let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { sentences.append(s) }
                    current = ""
                    // Skip the whitespace
                    i += 1
                    while i < chars.count && chars[i].isWhitespace { i += 1 }
                    continue
                }
            }
            i += 1
        }

        // Remaining text
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }

        return sentences
    }

    // MARK: - Heading detection

    /// Detect if a line is likely a heading.
    /// Criteria: short (<80 chars), non-empty, and either starts with # or is mostly title case.
    static func isHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 80 else { return false }

        // Markdown-style headings
        if trimmed.hasPrefix("#") { return true }

        // All-caps headings (at least 3 characters)
        if trimmed.count >= 3 && trimmed == trimmed.uppercased() && trimmed.contains(where: { $0.isLetter }) {
            return true
        }

        // Title case heuristic: most words start with uppercase
        let words = trimmed.split(separator: " ")
        guard words.count >= 1, words.count <= 12 else { return false }
        let capitalizedWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
        // At least 60% of words capitalized and no sentence-ending punctuation
        let ratio = Float(capitalizedWords.count) / Float(words.count)
        let endsWithPunctuation = trimmed.last == "." || trimmed.last == "," || trimmed.last == ";"
        return ratio >= 0.6 && !endsWithPunctuation && words.count >= 2
    }

    // MARK: - Private helpers

    private struct Section {
        let hierarchy: [String]
        let body: String
        let bodyStartChar: Int
    }

    private struct Paragraph {
        let text: String
        let startChar: Int
    }

    /// Split text into sections by detecting heading lines.
    private static func splitIntoSections(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: "\n")
        var sections: [Section] = []
        var currentHeadings: [String] = []
        var bodyLines: [String] = []
        var bodyStartChar = 0
        var charOffset = 0

        for (i, line) in lines.enumerated() {
            let lineLen = line.count + 1 // +1 for newline

            // Check if this line is a heading: preceded by blank line (or first line) and is heading-like
            let precededByBlank = i == 0 || lines[i - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isHeading = precededByBlank && isHeadingLine(line)

            if isHeading {
                // Flush previous section
                let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    sections.append(Section(
                        hierarchy: currentHeadings,
                        body: body,
                        bodyStartChar: bodyStartChar
                    ))
                }
                bodyLines = []
                bodyStartChar = charOffset + lineLen

                // Determine heading level from markdown # or treat as flat
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let headingText: String
                if trimmed.hasPrefix("#") {
                    let hashes = trimmed.prefix(while: { $0 == "#" })
                    let level = hashes.count
                    headingText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Truncate hierarchy to appropriate level
                    while currentHeadings.count >= level {
                        currentHeadings.removeLast()
                    }
                } else {
                    headingText = trimmed
                }
                currentHeadings.append(headingText)
            } else {
                if bodyLines.isEmpty && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bodyStartChar = charOffset
                }
                bodyLines.append(line)
            }

            charOffset += lineLen
        }

        // Flush final section
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            sections.append(Section(
                hierarchy: currentHeadings,
                body: body,
                bodyStartChar: bodyStartChar
            ))
        }

        // If no sections were created (no headings), return entire text as one section
        if sections.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(Section(
                hierarchy: [],
                body: text.trimmingCharacters(in: .whitespacesAndNewlines),
                bodyStartChar: 0
            ))
        }

        return sections
    }

    /// Split section body into paragraphs by double-newline.
    private static func splitParagraphs(_ text: String) -> [Paragraph] {
        let parts = text.components(separatedBy: "\n\n")
        var paragraphs: [Paragraph] = []
        var offset = 0

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Find actual start within the part
                let leadingWhitespace = part.prefix(while: { $0.isWhitespace }).count
                paragraphs.append(Paragraph(text: trimmed, startChar: offset + leadingWhitespace))
            }
            offset += part.count + 2 // +2 for \n\n separator
        }

        return paragraphs
    }
}
