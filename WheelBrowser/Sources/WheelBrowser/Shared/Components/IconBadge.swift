import SwiftUI

/// A reusable component for displaying an icon with a colored background
/// Used throughout the app for mention chips, suggestion rows, file icons, etc.
struct IconBadge: View {
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let iconWeight: Font.Weight
    let iconScale: CGFloat

    /// Create an icon badge with customizable appearance
    /// - Parameters:
    ///   - icon: SF Symbol name
    ///   - iconColor: Color for the icon
    ///   - backgroundColor: Background fill color
    ///   - size: Overall badge size (default: 24)
    ///   - cornerRadius: Corner radius (default: 5)
    ///   - iconWeight: Font weight for the icon (default: .medium)
    ///   - iconScale: Scale factor for icon relative to badge size (default: 0.5)
    init(
        icon: String,
        iconColor: Color,
        backgroundColor: Color,
        size: CGFloat = 24,
        cornerRadius: CGFloat = 5,
        iconWeight: Font.Weight = .medium,
        iconScale: CGFloat = 0.5
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.backgroundColor = backgroundColor
        self.size = size
        self.cornerRadius = cornerRadius
        self.iconWeight = iconWeight
        self.iconScale = iconScale
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * iconScale, weight: iconWeight))
            .foregroundColor(iconColor)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
            )
    }
}

// MARK: - Convenience Initializers

extension IconBadge {
    /// Create a mention-style badge with color-coordinated icon and faded background
    static func mention(icon: String, color: Color, size: CGFloat = 24) -> IconBadge {
        IconBadge(
            icon: icon,
            iconColor: color,
            backgroundColor: color.opacity(0.1),
            size: size,
            cornerRadius: 5
        )
    }

    /// Create a badge with white icon on solid color background
    static func solid(icon: String, backgroundColor: Color, size: CGFloat = 28) -> IconBadge {
        IconBadge(
            icon: icon,
            iconColor: .white,
            backgroundColor: backgroundColor,
            size: size,
            cornerRadius: 6,
            iconWeight: .semibold
        )
    }
}

// MARK: - Text Initial Badge

/// A badge showing a text initial (e.g., domain first letter) instead of an icon
struct TextInitialBadge: View {
    let text: String
    let textColor: Color
    let backgroundColor: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let fontSize: CGFloat?

    init(
        text: String,
        textColor: Color = .white,
        backgroundColor: Color,
        size: CGFloat = 28,
        cornerRadius: CGFloat = 6,
        fontSize: CGFloat? = nil
    ) {
        self.text = text
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.size = size
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
    }

    var body: some View {
        Text(text.prefix(1).uppercased())
            .font(.system(size: fontSize ?? size * 0.43, weight: .semibold))
            .foregroundColor(textColor)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Mention style badges
        HStack(spacing: 12) {
            IconBadge.mention(icon: "doc.text", color: .purple)
            IconBadge.mention(icon: "square.on.square", color: .blue)
            IconBadge.mention(icon: "brain.head.profile", color: .orange)
            IconBadge.mention(icon: "clock.arrow.circlepath", color: .green)
        }

        // Solid style badges
        HStack(spacing: 12) {
            IconBadge.solid(icon: "doc.fill", backgroundColor: .red)
            IconBadge.solid(icon: "archivebox.fill", backgroundColor: .brown)
            IconBadge.solid(icon: "photo.fill", backgroundColor: .blue)
        }

        // Text initial badges
        HStack(spacing: 12) {
            TextInitialBadge(text: "G", backgroundColor: .blue)
            TextInitialBadge(text: "A", backgroundColor: .purple)
            TextInitialBadge(text: "W", backgroundColor: .green)
        }
    }
    .padding()
}
