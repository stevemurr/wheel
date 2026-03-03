import SwiftUI
import MarkdownUI

/// Shared markdown theme for chat messages.
/// Used by both the OmniBar panel and full-screen chat.
enum ChatMarkdownTheme {

    /// Theme for user messages (white text on accent background)
    static var userTheme: Theme {
        Theme()
            .text {
                ForegroundColor(.white)
                FontSize(13.5)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.15))
                    .markdownMargin(top: 0, bottom: 6)
            }
            .code {
                ForegroundColor(.white.opacity(0.95))
                BackgroundColor(.white.opacity(0.15))
                FontSize(12)
            }
            .link {
                ForegroundColor(.white)
                UnderlineStyle(.single)
            }
    }

    /// Theme for assistant/system messages (rich markdown rendering)
    static var assistantTheme: Theme {
        Theme()
            .text {
                ForegroundColor(.primary)
                FontSize(13.5)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .markdownMargin(top: 0, bottom: 10)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(12)
                BackgroundColor(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
            }
            .codeBlock { configuration in
                CodeBlockView(
                    code: configuration.content,
                    language: configuration.language
                )
                .markdownMargin(top: 8, bottom: 8)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.purple.opacity(0.5))
                        .frame(width: 3)

                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(.secondary)
                            FontSize(13)
                        }
                        .padding(.leading, 12)
                }
                .markdownMargin(top: 6, bottom: 6)
            }
            .link {
                ForegroundColor(.accentColor)
            }
            .strong {
                FontWeight(.semibold)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle { FontSize(15); FontWeight(.bold) }
                    .markdownMargin(top: 14, bottom: 6)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle { FontSize(14); FontWeight(.bold) }
                    .markdownMargin(top: 12, bottom: 5)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle { FontSize(13.5); FontWeight(.semibold) }
                    .markdownMargin(top: 10, bottom: 4)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 4, bottom: 4)
            }
            .thematicBreak {
                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.4))
                    .markdownMargin(top: 12, bottom: 12)
            }
            .image { configuration in
                configuration.label
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: 500)
                    .markdownMargin(top: 8, bottom: 8)
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
                    .markdownMargin(top: 8, bottom: 12)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                        FontSize(12.5)
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
            }
    }

    /// Returns the appropriate theme for a message role
    static func theme(for role: ChatMessage.MessageRole) -> Theme {
        switch role {
        case .user:
            return userTheme
        default:
            return assistantTheme
        }
    }
}
