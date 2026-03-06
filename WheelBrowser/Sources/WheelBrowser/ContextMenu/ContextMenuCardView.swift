import SwiftUI

/// The floating context menu card with action rows (Zone A) and navigation chips (Zone B).
///
/// This view is stateless — all data and callbacks are passed in as parameters.
/// No `@ObservedObject` subscriptions, so only the overlay drives re-renders.
struct ContextMenuCardView: View {
    let sections: [ContextMenuSection]
    let canGoBack: Bool
    let canGoForward: Bool
    let highlightedIndex: Int?
    let onAction: (ContextMenuAction) -> Void
    let onHoverResetHighlight: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Zone A: Context-specific action rows
            if !sections.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        if sectionIndex > 0 {
                            Divider().padding(.horizontal, 8)
                        }
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { _, item in
                            ContextMenuRow(
                                item: item,
                                isHighlighted: isHighlighted(item),
                                onTap: { onAction(item.action) },
                                onHover: onHoverResetHighlight
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider().padding(.horizontal, 8)
            }

            // Zone B: Navigation chip bar
            HStack(spacing: 6) {
                NavigationChip(label: "Back", systemImage: "chevron.left", isEnabled: canGoBack) {
                    onAction(.goBack)
                }
                NavigationChip(label: "Forward", systemImage: "chevron.right", isEnabled: canGoForward) {
                    onAction(.goForward)
                }
                NavigationChip(label: "Reload", systemImage: "arrow.clockwise", isEnabled: true) {
                    onAction(.reload)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 200, maxWidth: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 20, x: 0, y: 8)
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
    let onHover: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered || isHighlighted
                          ? Color(nsColor: .controlAccentColor).opacity(0.15)
                          : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.4)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }
}

// MARK: - Navigation Chip

private struct NavigationChip: View {
    let label: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHovered
                          ? Color(nsColor: .controlAccentColor).opacity(0.15)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundStyle(isEnabled ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}
