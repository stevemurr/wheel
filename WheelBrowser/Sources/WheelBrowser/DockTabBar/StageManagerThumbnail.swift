import SwiftUI
import AppKit

/// Individual tab thumbnail in the Stage Manager strip.
/// Rendered with a 3D Y-axis tilt so thumbnails appear "turned" like in macOS Stage Manager.
struct StageManagerThumbnail: View {
    static let baseThumbnailWidth: CGFloat = 110
    static let baseThumbnailHeight: CGFloat = 70

    var tab: Tab
    var screenshotManager: TabScreenshotManager
    let isActive: Bool
    let isSelected: Bool
    let canClose: Bool
    let selectionTint: Color
    let groupColor: Color?
    let sizeScale: CGFloat
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    /// Y-axis rotation angle in degrees — tilts the thumbnail so the
    /// right edge appears closer and the left edge recedes.
    private let tiltAngle: Double = 8

    private var thumbnailWidth: CGFloat { Self.baseThumbnailWidth * sizeScale }
    private var thumbnailHeight: CGFloat { Self.baseThumbnailHeight * sizeScale }
    private var cornerRadius: CGFloat { 8 * sizeScale }
    private var titleFontSize: CGFloat { max(8, 9 * sizeScale) }
    private var titleHorizontalPadding: CGFloat { max(4, 6 * sizeScale) }
    private var titleVerticalPadding: CGFloat { max(2, 3 * sizeScale) }
    private var closeButtonFontSize: CGFloat { max(12, 14 * sizeScale) }
    private var placeholderFontSize: CGFloat { max(16, 20 * sizeScale) }
    private var loadingPadding: CGFloat { max(3, 4 * sizeScale) }
    private var groupAccentColor: Color? { groupColor }
    private var groupTintOpacity: Double { isActive ? 0.18 : 0.11 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if let groupAccentColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [groupAccentColor.opacity(groupTintOpacity), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .overlay(alignment: .bottom) {
                    titleOverlay
                }
                .overlay {
                    if tab.showsAgentAutomationUI {
                        AgentRoundedGlow(cornerRadius: cornerRadius, lineWidth: 2.2, fillOpacity: 0.028)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    }
                }
                .overlay {
                    if tab.isLoading && !tab.showsAgentAutomationUI {
                        loadingIndicator
                    }
                }

            // Close button (hover-reveal)
            if isHovered && canClose && !tab.showsAgentAutomationUI {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: closeButtonFontSize))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .padding(loadingPadding)
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
            color: tab.showsAgentAutomationUI
                ? Color.green.opacity(isActive ? 0.45 : 0.3)
                : (groupAccentColor?.opacity(isActive ? 0.34 : 0.22)
                    ?? .black.opacity(isActive ? 0.45 : 0.3)),
            radius: tab.showsAgentAutomationUI ? (isActive ? 14 : 10) : (isActive ? 8 : 5),
            x: isActive ? 3 : 2,
            y: isActive ? 3 : 2
        )
        .onTapGesture {
            onSelect(NSApp.currentEvent?.modifierFlags ?? [])
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tab.showsAgentAutomationUI ? "\(tab.displayTitle) (Agent running)" : tab.displayTitle)
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
            if let groupAccentColor {
                LinearGradient(
                    colors: [groupAccentColor.opacity(0.5), groupAccentColor.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                DomainGradient.placeholderGradient(for: tab.url?.host)
            }

            if groupAccentColor != nil {
                Image(systemName: "globe")
                    .font(.system(size: placeholderFontSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
            } else if let host = tab.url?.host {
                Text(DomainGradient.initial(for: host))
                    .font(.system(size: placeholderFontSize, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: placeholderFontSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Title Overlay

    private var titleOverlay: some View {
        Text(tab.title)
            .font(.system(size: titleFontSize, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, titleHorizontalPadding)
            .padding(.vertical, titleVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        .clear,
                        (groupAccentColor ?? .black).opacity(groupAccentColor == nil ? 0.6 : 0.52)
                    ],
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
                .padding(loadingPadding)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(loadingPadding)
    }

    // MARK: - Styling

    private var borderColor: Color {
        if tab.showsAgentAutomationUI {
            return Color.green.opacity(0.9)
        } else if let groupAccentColor {
            return groupAccentColor.opacity(isActive ? 0.92 : (isSelected ? 0.62 : 0.34))
        } else if isActive {
            return Color(nsColor: .controlAccentColor)
        } else if isSelected {
            return selectionTint.opacity(0.92)
        } else {
            return Color.white.opacity(0.15)
        }
    }

    private var borderWidth: CGFloat {
        if tab.showsAgentAutomationUI {
            return 2
        } else if groupAccentColor != nil {
            return isActive ? 2.1 : (isSelected ? 1.4 : 0.7)
        } else if isActive {
            return 2.5
        } else if isSelected {
            return 1.6
        } else {
            return 0.5
        }
    }
}
