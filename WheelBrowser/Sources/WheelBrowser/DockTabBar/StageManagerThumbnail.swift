import SwiftUI

/// Individual tab thumbnail in the Stage Manager strip.
/// Rendered with a 3D Y-axis tilt so thumbnails appear "turned" like in macOS Stage Manager.
struct StageManagerThumbnail: View {
    @ObservedObject var tab: Tab
    @ObservedObject var screenshotManager: TabScreenshotManager
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    private let thumbnailWidth: CGFloat = 110
    private let thumbnailHeight: CGFloat = 70
    private let cornerRadius: CGFloat = 8

    /// Y-axis rotation angle in degrees — tilts the thumbnail so the
    /// right edge appears closer and the left edge recedes.
    private let tiltAngle: Double = 8

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .bottom) {
                    titleOverlay
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .overlay {
                    if tab.isLoading && !tab.hasActiveAgent {
                        loadingIndicator
                    }
                }

            // Close button (hover-reveal)
            if isHovered && canClose && !tab.hasActiveAgent {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        // 3D tilt: rotate around Y-axis with perspective
        .rotation3DEffect(
            .degrees(isHovered ? 0 : tiltAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: .trailing,
            perspective: 0.5
        )
        .scaleEffect(isHovered ? 1.05 : (isActive ? 1.0 : 0.95))
        .animation(AppAnimation.hoverSpring, value: isHovered)
        // Floating shadow — stronger for active tab
        .shadow(
            color: .black.opacity(isActive ? 0.45 : 0.3),
            radius: isActive ? 8 : 5,
            x: isActive ? 3 : 2,
            y: isActive ? 3 : 2
        )
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tab.hasActiveAgent ? "\(tab.displayTitle) (Agent running)" : tab.displayTitle)
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        if let screenshot = screenshotManager.getScreenshot(for: tab.id) {
            Image(nsImage: screenshot)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholderView
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            if tab.isChatTab {
                LinearGradient(
                    colors: [.purple.opacity(0.4), .purple.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                DomainGradient.placeholderGradient(for: tab.url?.host)
            }

            if tab.isChatTab {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.purple.opacity(0.8))
            } else if let host = tab.url?.host {
                Text(DomainGradient.initial(for: host))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Title Overlay

    private var titleOverlay: some View {
        Text(tab.title)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: cornerRadius,
                        bottomTrailing: cornerRadius,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
            )
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        VStack {
            ProgressView()
                .controlSize(.small)
                .padding(4)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }

    // MARK: - Styling

    private var borderColor: Color {
        if tab.hasActiveAgent {
            return .green
        } else if isActive {
            return Color(nsColor: .controlAccentColor)
        } else {
            return Color.white.opacity(0.15)
        }
    }

    private var borderWidth: CGFloat {
        if tab.hasActiveAgent {
            return 2
        } else if isActive {
            return 2.5
        } else {
            return 0.5
        }
    }
}
