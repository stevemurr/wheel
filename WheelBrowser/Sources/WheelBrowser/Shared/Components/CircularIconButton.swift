import SwiftUI

/// A circular button with an icon, commonly used for panel toggles
struct CircularIconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 28
    var iconSize: CGFloat = 12

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(AppAnimation.hoverSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// A circular button with customizable icon and background colors
struct ColoredCircularIconButton: View {
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    let action: () -> Void
    var size: CGFloat = 22
    var iconSize: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }
}
