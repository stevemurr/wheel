import SwiftUI

/// A reusable panel that appears above the OmniBar for different modes
struct OmniPanel<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let borderColor: Color
    let subtitle: String?
    let menuContent: (() -> AnyView)?
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    private let maxHeight: CGFloat = WindowConstants.omniPanelMaxHeight
    private let maxWidth: CGFloat = WindowConstants.omniPanelMaxWidth

    init(
        title: String,
        icon: String,
        iconColor: Color = .accentColor,
        borderColor: Color = .blue,
        subtitle: String? = nil,
        menuContent: (() -> AnyView)? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.borderColor = borderColor
        self.subtitle = subtitle
        self.menuContent = menuContent
        self.onDismiss = onDismiss
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .opacity(0.5)

            // Content area
            content()
        }
        .frame(maxWidth: maxWidth)
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(WindowConstants.panelShadowOpacity), radius: WindowConstants.panelShadowRadius, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                .stroke(borderColor.opacity(0.5), lineWidth: 1.0)
        )
        .clipShape(RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: WindowConstants.headlineFontSize, weight: .semibold))
                .foregroundColor(iconColor)

            Text(title)
                .font(.system(size: WindowConstants.headlineFontSize, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: WindowConstants.bodyFontSize))
                    .foregroundColor(.secondary)
            }

            if let menuContent = menuContent {
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: WindowConstants.bodyFontSize, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: WindowConstants.iconButtonSize, height: WindowConstants.iconButtonSize)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: WindowConstants.bodyFontSize, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: WindowConstants.iconButtonSize, height: WindowConstants.iconButtonSize)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WindowConstants.headerPadding)
        .padding(.vertical, 10)
        .background(Color(nsColor: .separatorColor).opacity(0.05))
    }
}
