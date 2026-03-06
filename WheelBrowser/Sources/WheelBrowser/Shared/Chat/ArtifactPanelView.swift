import SwiftUI
import MarkdownUI

/// Vertical panel for viewing a single artifact (code, markdown, html, json).
struct ArtifactPanelView: View {
    let artifact: ChatArtifact
    var onClose: () -> Void

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            Divider()

            // Content area
            contentArea
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Language badge
            if let language = artifact.language {
                Text(language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            // Title
            Text(artifact.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Copy button
            Button(action: copyContent) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(showCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch artifact.type {
        case .code:
            codeView
        case .markdown:
            markdownView
        case .json:
            jsonView
        case .html:
            htmlView
        case .plainText:
            plainTextView
        }
    }

    private var codeView: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                let lines = artifact.content.components(separatedBy: "\n")
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 0) {
                        // Line number
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                            .frame(minWidth: lineNumberWidth, alignment: .trailing)
                            .padding(.trailing, 12)

                        // Highlighted line
                        Text(SyntaxHighlighter.highlight(line, language: artifact.language))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(14)
        }
    }

    private var markdownView: some View {
        ScrollView {
            Markdown(artifact.content)
                .markdownTheme(ChatMarkdownTheme.assistantTheme(compact: false))
                .textSelection(.enabled)
                .padding(14)
        }
    }

    private var jsonView: some View {
        ScrollView(.vertical) {
            let prettyPrinted = prettyPrintJSON(artifact.content)
            let lines = prettyPrinted.components(separatedBy: "\n")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                            .frame(minWidth: lineNumberWidth, alignment: .trailing)
                            .padding(.trailing, 12)

                        Text(SyntaxHighlighter.highlight(line, language: "json"))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(14)
        }
    }

    private var htmlView: some View {
        ScrollView(.vertical) {
            Text(SyntaxHighlighter.highlight(artifact.content, language: "html"))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
        }
    }

    private var plainTextView: some View {
        ScrollView {
            Text(artifact.content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    // MARK: - Helpers

    private var lineNumberWidth: CGFloat {
        let lineCount = artifact.content.components(separatedBy: "\n").count
        let digits = String(lineCount).count
        return CGFloat(digits) * 7 + 4
    }

    private func copyContent() {
        PasteboardHelper.copy(artifact.content)
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopied = false
        }
    }

    private func prettyPrintJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return result
    }
}
