import SwiftUI
import AppKit

struct TabWheelItem: View {
    let tab: Tab
    let isSelected: Bool
    let size: CGFloat
    let scale: CGFloat
    @ObservedObject var screenshotManager: TabScreenshotManager

    @State private var isHovered = false

    // Preview dimensions based on scale
    private var previewWidth: CGFloat {
        size * 2.2 * scale
    }

    private var previewHeight: CGFloat {
        size * 1.4 * scale
    }

    private var cornerRadius: CGFloat {
        8 * scale
    }

    var body: some View {
        VStack(spacing: 4 * scale) {
            // Screenshot preview card
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: previewWidth, height: previewHeight)

                if let screenshot = screenshotManager.getScreenshot(for: tab.id) {
                    Image(nsImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: previewWidth - 4, height: previewHeight - 4)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2))
                } else {
                    // Fallback placeholder
                    previewPlaceholder
                }

                // Selection ring
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: previewWidth + 4, height: previewHeight + 4)
                }

                // Hover highlight
                if isHovered && !isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(nsColor: .labelColor).opacity(0.4), lineWidth: 2)
                        .frame(width: previewWidth + 2, height: previewHeight + 2)
                }
            }
            .shadow(color: .black.opacity(0.2 * Double(scale)), radius: 6 * scale, x: 0, y: 3 * scale)

            // Title with pill background
            if isSelected || scale > 0.7 {
                Text(displayTitle)
                    .font(.system(size: max(9, 11 * scale), weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 3 * scale)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.75))
                    )
                    .frame(maxWidth: previewWidth + 20)
                    .opacity(scale > 0.6 ? 1.0 : 0.0)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .scaleEffect(isHovered && !isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: scale)
    }

    // MARK: - Placeholder

    private var previewPlaceholder: some View {
        ZStack {
            // Gradient background
            RoundedRectangle(cornerRadius: cornerRadius - 2)
                .fill(domainGradient)
                .frame(width: previewWidth - 4, height: previewHeight - 4)

            // Domain initial
            Text(domainInitial)
                .font(.system(size: max(16, 28 * scale), weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    // MARK: - Helpers

    private var displayTitle: String {
        if tab.title.isEmpty || tab.title == "New Tab" {
            if let host = tab.url?.host {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return "New Tab"
        }
        return tab.title
    }

    private var domainInitial: String {
        DomainGradient.initial(for: tab.url?.host)
    }

    private var domainGradient: LinearGradient {
        DomainGradient.gradient(for: tab.url?.host)
    }
}
