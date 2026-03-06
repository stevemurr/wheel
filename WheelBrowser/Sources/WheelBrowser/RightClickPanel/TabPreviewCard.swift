import SwiftUI

/// A larger preview card for tabs showing visual thumbnail and title
struct TabPreviewCard: View {
    var tab: Tab
    var screenshotManager: TabScreenshotManager
    let isActive: Bool
    let isHovered: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var showClose = false

    private let cardWidth: CGFloat = 160
    private let thumbnailHeight: CGFloat = 100
    private let titleHeight: CGFloat = 24
    private let cornerRadius: CGFloat = 8

    private var cardHeight: CGFloat {
        thumbnailHeight + titleHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: cardWidth, height: thumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                // Close button overlay
                if showClose && canClose && !tab.hasActiveAgent {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )

            // Title area
            Text(tab.title)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cardWidth, height: titleHeight, alignment: .center)
                .padding(.horizontal, 4)
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(AppAnimation.hoverSpring, value: isHovered)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            showClose = hovering
        }
        .help(tab.title)
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        if let screenshot = screenshotManager.getScreenshot(for: tab.id) {
            Image(nsImage: screenshot)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Placeholder
            placeholderView
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            // Gradient background
            DomainGradient.placeholderGradient(for: tab.url?.host)

            // Icon or initial
            if let host = tab.url?.host {
                Text(DomainGradient.initial(for: host))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Styling

    private var borderColor: Color {
        if tab.hasActiveAgent {
            return .green
        } else if isActive {
            return Color(nsColor: .controlAccentColor)
        } else {
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        if tab.hasActiveAgent {
            return 2
        } else if isActive {
            return 2.5
        } else {
            return 0
        }
    }
}
