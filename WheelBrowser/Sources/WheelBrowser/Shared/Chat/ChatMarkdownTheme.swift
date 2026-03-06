import SwiftUI
import MarkdownUI

/// Shared markdown theme for chat messages.
/// Used by both the OmniBar panel and full-screen chat.
enum ChatMarkdownTheme {

    /// Theme for user messages (white text on accent background)
    static func userTheme(compact: Bool) -> Theme {
        let bodySize: CGFloat = compact ? 13.5 : 14.5

        return Theme()
            .text {
                ForegroundColor(.primary)
                FontSize(bodySize)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .markdownMargin(top: 0, bottom: compact ? 6 : 8)
            }
            .code {
                ForegroundColor(.primary)
                BackgroundColor(Color.accentColor.opacity(0.08))
                FontSize(compact ? 12 : 12.5)
            }
            .link {
                ForegroundColor(.accentColor)
            }
            .strong {
                FontWeight(.semibold)
            }
    }

    /// Theme for assistant/system messages (rich markdown rendering)
    static func assistantTheme(compact: Bool) -> Theme {
        let bodySize: CGFloat = compact ? 13.5 : 15
        let paragraphSpacing: CGFloat = compact ? 10 : 12
        let blockMargin: CGFloat = compact ? 8 : 10

        return Theme()
            .text {
                ForegroundColor(.primary)
                FontSize(bodySize)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(compact ? 0.18 : 0.24))
                    .markdownMargin(top: 0, bottom: paragraphSpacing)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(compact ? 12 : 12.5)
                BackgroundColor(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            }
            .codeBlock { configuration in
                CodeBlockView(
                    code: configuration.content,
                    language: configuration.language
                )
                .markdownMargin(top: blockMargin, bottom: blockMargin + 2)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(nsColor: .separatorColor).opacity(0.7))
                        .frame(width: 3)

                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(.secondary)
                            FontSize(compact ? 13 : 14)
                        }
                        .padding(.leading, 12)
                }
                .markdownMargin(top: 8, bottom: 8)
            }
            .link {
                ForegroundColor(.accentColor)
            }
            .strong {
                FontWeight(.semibold)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(compact ? 18 : 28)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: compact ? 14 : 22, bottom: compact ? 6 : 8)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(compact ? 16 : 22)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: compact ? 12 : 18, bottom: compact ? 5 : 7)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(compact ? 14.5 : 18)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: compact ? 10 : 14, bottom: compact ? 4 : 6)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: compact ? 4 : 6, bottom: compact ? 4 : 6)
            }
            .thematicBreak {
                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.4))
                    .markdownMargin(top: compact ? 12 : 16, bottom: compact ? 12 : 16)
            }
            .image { configuration in
                configuration.label
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: 500)
                    .markdownMargin(top: blockMargin, bottom: blockMargin)
            }
            // Table styling
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(
                        TableBorderStyle(
                            .allBorders,
                            color: Color(nsColor: .separatorColor).opacity(0.4),
                            width: 1
                        )
                    )
                    .markdownTableBackgroundStyle(
                        .alternatingRows(
                            Color(nsColor: .controlBackgroundColor).opacity(0.3),
                            Color.clear,
                            header: Color(nsColor: .controlBackgroundColor).opacity(0.6)
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
                    )
                    .markdownMargin(top: blockMargin, bottom: compact ? 12 : 14)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                        FontSize(compact ? 12.5 : 13)
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
            }
    }

    /// Returns the appropriate theme for a message role
    static func theme(for role: ChatMessage.MessageRole, compact: Bool = false) -> Theme {
        switch role {
        case .user:
            return userTheme(compact: compact)
        default:
            return assistantTheme(compact: compact)
        }
    }
}
