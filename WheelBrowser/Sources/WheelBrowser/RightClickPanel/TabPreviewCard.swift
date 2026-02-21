import SwiftUI

/// A larger preview card for tabs showing visual thumbnail and title
struct TabPreviewCard: View {
    @ObservedObject var tab: Tab
    @ObservedObject var screenshotManager: TabScreenshotManager
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
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
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
            LinearGradient(
                colors: placeholderColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Icon or initial
            if let url = tab.url, let host = url.host {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
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

    private var placeholderColors: [Color] {
        if let url = tab.url, let host = url.host {
            let hash = abs(host.hashValue)
            let hue1 = Double(hash % 360) / 360.0
            let hue2 = Double((hash / 360) % 360) / 360.0

            return [
                Color(hue: hue1, saturation: 0.3, brightness: 0.4),
                Color(hue: hue2, saturation: 0.3, brightness: 0.3)
            ]
        } else {
            return [
                Color(nsColor: .systemGray).opacity(0.3),
                Color(nsColor: .systemGray).opacity(0.2)
            ]
        }
    }

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

// MARK: - Large Add Button

struct LargeAddButton: View {
    let action: () -> Void

    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private let thumbnailHeight: CGFloat = 100
    private let cornerRadius: CGFloat = 8

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(isHovered ? 0.5 : 0.3))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .frame(width: cardWidth, height: thumbnailHeight)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
