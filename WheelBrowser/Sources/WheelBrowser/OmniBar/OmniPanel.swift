import SwiftUI

/// A reusable panel that appears above the OmniBar for different modes
struct OmniPanel<Content: View, MenuContent: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let borderColor: Color
    let subtitle: String?
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content
    private let menuContent: (() -> MenuContent)?

    @Environment(\.colorScheme) private var currentColorScheme

    private let maxHeight: CGFloat = WindowConstants.omniPanelMaxHeight
    private let maxWidth: CGFloat = WindowConstants.omniPanelMaxWidth

    init(
        title: String,
        icon: String,
        iconColor: Color = .accentColor,
        borderColor: Color = .blue,
        subtitle: String? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) where MenuContent == EmptyView {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.borderColor = borderColor
        self.subtitle = subtitle
        self.menuContent = nil
        self.onDismiss = onDismiss
        self.content = content
    }

    init(
        title: String,
        icon: String,
        iconColor: Color = .accentColor,
        borderColor: Color = .blue,
        subtitle: String? = nil,
        @ViewBuilder menuContent: @escaping () -> MenuContent,
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
            ZStack {
                RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                    .fill(panelBaseFill)

                RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(currentColorScheme == .dark ? 0.18 : 0.10)

                RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                    .fill(borderColor.opacity(currentColorScheme == .dark ? 0.04 : 0.025))
            }
            .shadow(color: panelShadowColor, radius: WindowConstants.panelShadowRadius + 4, x: 0, y: 6)
        )
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                    .stroke(borderColor.opacity(currentColorScheme == .dark ? 0.30 : 0.16), lineWidth: 1.0)

                RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous)
                    .stroke(panelInnerHighlight, lineWidth: 1.0)
                    .padding(1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: WindowConstants.panelCornerRadius, style: .continuous))
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
        .background(panelHeaderFill)
    }

    private var panelBaseFill: Color {
        if currentColorScheme == .dark {
            return Color(nsColor: .windowBackgroundColor)
        }

        return Color(red: 0.989, green: 0.985, blue: 0.978)
    }

    private var panelHeaderFill: Color {
        if currentColorScheme == .dark {
            return Color.white.opacity(0.04)
        }

        return Color.black.opacity(0.025)
    }

    private var panelInnerHighlight: Color {
        currentColorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.86)
    }

    private var panelShadowColor: Color {
        Color.black.opacity(currentColorScheme == .dark ? 0.30 : WindowConstants.panelShadowOpacity + 0.06)
    }
}
