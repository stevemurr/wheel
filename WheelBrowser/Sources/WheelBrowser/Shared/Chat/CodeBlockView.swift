import SwiftUI

/// Syntax-highlighted code block with language label, copy button, and optional line numbers.
struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var showCopied = false
    @State private var isHovered = false

    private var normalizedLanguage: String? {
        SyntaxHighlighter.normalizeLanguage(language)
    }

    private var displayLanguage: String {
        normalizedLanguage ?? "code"
    }

    private var lines: [String] {
        code.components(separatedBy: "\n")
    }

    private var showLineNumbers: Bool {
        lines.count > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            headerBar

            Divider()
                .opacity(0.3)

            // Code content
            codeContent
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            // Language label
            Text(displayLanguage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Copy button
            Button(action: copyCode) {
                HStack(spacing: 3) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    Text(showCopied ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(showCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || showCopied ? 1.0 : 0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Code Content

    private var codeContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line numbers
            if showLineNumbers {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                            .frame(minWidth: lineNumberWidth, alignment: .trailing)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))

                Divider()
                    .opacity(0.2)
            }

            // Highlighted code
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(SyntaxHighlighter.highlight(line, language: normalizedLanguage))
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Helpers

    private var lineNumberWidth: CGFloat {
        let digits = String(lines.count).count
        return CGFloat(digits) * 8 + 4
    }

    private func copyCode() {
        PasteboardHelper.copy(code)
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopied = false
        }
    }
}
