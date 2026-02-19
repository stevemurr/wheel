import SwiftUI
import MarkdownUI

/// View that renders AI widget content based on layout configuration
struct AIWidgetContentView: View {
    let config: AIWidgetConfig
    let content: ExtractedContent
    let size: WidgetSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if config.display.showTitle && size != .small {
                HStack {
                    Image(systemName: config.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(config.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let error = content.error {
                errorView(error)
            } else if content.items.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var contentView: some View {
        switch config.display.layout {
        case .list:
            listView
        case .cards:
            cardsView
        case .singleValue:
            singleValueView
        case .markdown:
            markdownView
        }
    }

    // MARK: - List Layout

    private var listView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(content.items.prefix(itemLimit)) { item in
                ListItemView(item: item, template: config.display.template, accentColor: accentColor)
            }
        }
    }

    // MARK: - Cards Layout

    private var cardsView: some View {
        let columns = size == .small ? 1 : (size == .large || size == .extraLarge ? 2 : 1)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(content.items.prefix(itemLimit)) { item in
                CardItemView(item: item, template: config.display.template, accentColor: accentColor)
            }
        }
    }

    // MARK: - Single Value Layout

    private var singleValueView: some View {
        Group {
            if let item = content.items.first {
                SingleValueItemView(item: item, template: config.display.template, accentColor: accentColor, size: size)
            } else {
                emptyView
            }
        }
    }

    // MARK: - Markdown Layout

    private var markdownView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(content.items.prefix(itemLimit)) { item in
                    let rendered = renderTemplate(config.display.template, with: item.fields)
                    Markdown(rendered)
                        .markdownTextStyle {
                            FontSize(13)
                        }
                }
            }
        }
    }

    // MARK: - Error & Empty States

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No content")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var itemLimit: Int {
        switch size {
        case .small:
            return min(3, config.display.itemLimit)
        case .medium:
            return min(5, config.display.itemLimit)
        case .large, .extraLarge:
            return config.display.itemLimit
        case .wide:
            return min(4, config.display.itemLimit)
        }
    }

    private var accentColor: Color {
        if let hex = config.display.accentColor {
            return Color(hex: hex) ?? .accentColor
        }
        return .accentColor
    }
}

// MARK: - List Item View

struct ListItemView: View {
    let item: ExtractedItem
    let template: String
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        Button {
            if let link = item.link {
                NotificationCenter.default.post(name: .openURL, object: link)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(accentColor.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    if let title = item.fields["title"] {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    if let description = item.fields["description"] {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let meta = item.fields["date"] ?? item.fields["author"] {
                        Text(meta)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(item.link == nil)
    }
}

// MARK: - Card Item View

struct CardItemView: View {
    let item: ExtractedItem
    let template: String
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        Button {
            if let link = item.link {
                NotificationCenter.default.post(name: .openURL, object: link)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let title = item.fields["title"] {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if let description = item.fields["description"] {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                HStack {
                    if let author = item.fields["author"] {
                        Text(author)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let date = item.fields["date"] {
                        Text(date)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovered ? accentColor.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(item.link == nil)
    }
}

// MARK: - Single Value View

struct SingleValueItemView: View {
    let item: ExtractedItem
    let template: String
    let accentColor: Color
    let size: WidgetSize

    var body: some View {
        VStack(spacing: 4) {
            if let value = item.fields["value"] ?? item.fields.values.first {
                Text(value)
                    .font(.system(size: size == .small ? 32 : 48, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
            }

            if let label = item.fields["label"] ?? item.fields["title"] {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let subtitle = item.fields["subtitle"] ?? item.fields["description"] {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Template Rendering

func renderTemplate(_ template: String, with fields: [String: String]) -> String {
    var result = template
    for (key, value) in fields {
        result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    // Remove any unreplaced placeholders
    result = result.replacingOccurrences(of: #"\{\{[^}]+\}\}"#, with: "", options: .regularExpression)
    return result
}

