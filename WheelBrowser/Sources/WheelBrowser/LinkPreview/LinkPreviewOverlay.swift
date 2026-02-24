import SwiftUI

struct LinkPreviewOverlay: View {
    @ObservedObject var state = LinkPreviewState.shared
    let containerSize: CGSize

    private let panelWidth: CGFloat = 320
    private let panelMaxHeight: CGFloat = 200
    private let panelCornerRadius: CGFloat = 10
    private let panelPadding: CGFloat = 12
    private let edgeMargin: CGFloat = 12

    var body: some View {
        if state.isVisible, let url = state.linkURL {
            previewPanel(for: url)
                .position(clampedPosition)
        }
    }

    private func previewPanel(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            if let title = state.pageTitle {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .lineLimit(2)
            } else if state.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }

            // Domain
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)

            // Summary or loading state
            if let summary = state.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = state.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .systemRed))
                    .lineLimit(2)
            } else if state.isLoading && state.pageTitle != nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("Generating summary...")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
        .padding(panelPadding)
        .frame(width: panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.98))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var clampedPosition: CGPoint {
        var x = state.position.x
        var y = state.position.y

        let halfWidth = panelWidth / 2
        let estimatedHeight: CGFloat = 120 // Estimate for clamping

        // Clamp X to stay within bounds
        x = max(halfWidth + edgeMargin, min(x, containerSize.width - halfWidth - edgeMargin))

        // If would overflow bottom, flip above the link
        if y + estimatedHeight > containerSize.height - edgeMargin {
            // Position above the link (subtract estimated height and some offset)
            y = state.position.y - estimatedHeight - 20
        }

        // Clamp Y to stay within top bound
        y = max(estimatedHeight / 2 + edgeMargin, y)

        return CGPoint(x: x, y: y)
    }
}
