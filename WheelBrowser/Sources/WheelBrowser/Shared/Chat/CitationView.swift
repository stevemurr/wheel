import SwiftUI

/// Renders citation references like [1], [2] as tappable superscript badges with source info on hover.
struct CitationBadge: View {
    let number: Int
    let sourceTitle: String?
    let sourceURL: String?

    @State private var isHovered = false

    var body: some View {
        Text("[\(number)]")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.accentColor)
            .baselineOffset(4)
            .onHover { hovering in
                isHovered = hovering
            }
            .popover(isPresented: $isHovered, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = sourceTitle {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                    }
                    if let url = sourceURL {
                        Text(url)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: 300)
            }
    }
}

/// Parses citation references from assistant content when page contexts were used.
enum CitationParser {
    struct Citation {
        let number: Int
        let range: Range<String.Index>
    }

    /// Find all [N] citation references in text
    static func findCitations(in text: String) -> [Citation] {
        let pattern = #"\[(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match -> Citation? in
            let numberRange = match.range(at: 1)
            guard numberRange.length > 0 else { return nil }
            let numberStr = nsText.substring(with: numberRange)
            guard let number = Int(numberStr), number > 0, number <= 20 else { return nil }

            guard let range = Range(match.range, in: text) else { return nil }
            return Citation(number: number, range: range)
        }
    }
}
