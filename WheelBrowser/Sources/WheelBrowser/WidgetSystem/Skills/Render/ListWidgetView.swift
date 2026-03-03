import SwiftUI

/// Renders a `RenderInput.list` as a scrollable list of items.
struct ListWidgetView: View {
    let title: String
    let items: [ListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ListItemRow(item: item)
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }
}

private struct ListItemRow: View {
    let item: ListItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.headline)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)

                if let subheadline = item.subheadline {
                    Text(subheadline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let badge = item.badge {
                Text(badge.text)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor(badge.color).opacity(0.15))
                    .foregroundStyle(badgeColor(badge.color))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let link = item.link, let url = URL(string: link) {
                NotificationCenter.default.post(name: .openURL, object: url)
            }
        }
    }

    private func badgeColor(_ color: ListItem.Badge.BadgeColor) -> Color {
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .gray: return .gray
        }
    }
}
