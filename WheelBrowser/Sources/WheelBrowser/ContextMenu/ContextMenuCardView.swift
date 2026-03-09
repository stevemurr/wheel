import SwiftUI

/// Compact browser-style context menu card.
struct ContextMenuCardView: View {
    let sections: [ContextMenuSection]
    let highlightedIndex: Int?
    let onAction: (ContextMenuAction) -> Void
    let onHoverChange: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                if sectionIndex > 0 {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }

                ForEach(section.items) { item in
                    ContextMenuRow(
                        item: item,
                        isHighlighted: isHighlighted(item),
                        onTap: { onAction(item.action) },
                        onHoverChange: { hovering in
                            onHoverChange(hovering && item.isEnabled ? item.id : nil)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 220, maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .inset(by: 0.5)
                .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.32), radius: 22, x: 0, y: 10)
    }

    private func isHighlighted(_ item: ContextMenuItem) -> Bool {
        guard let index = highlightedIndex else { return false }
        let enabledItems = sections.flatMap(\.items).filter(\.isEnabled)
        guard let itemIndex = enabledItems.firstIndex(where: { $0.id == item.id }) else { return false }
        return itemIndex == index
    }
}

// MARK: - Context Menu Row

private struct ContextMenuRow: View {
    let item: ContextMenuItem
    let isHighlighted: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(item.title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .foregroundStyle(foregroundStyle)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackgroundColor)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .onHover { hovering in
            isHovered = item.isEnabled && hovering
            onHoverChange(hovering)
        }
    }

    private var rowBackgroundColor: Color {
        if !item.isEnabled {
            return .clear
        }
        if isHovered || isHighlighted {
            return Color(nsColor: .controlAccentColor)
        }
        return .clear
    }

    private var foregroundStyle: Color {
        if !item.isEnabled {
            return Color(nsColor: .tertiaryLabelColor)
        }
        if isHovered || isHighlighted {
            return .white
        }
        return Color(nsColor: .labelColor)
    }
}
