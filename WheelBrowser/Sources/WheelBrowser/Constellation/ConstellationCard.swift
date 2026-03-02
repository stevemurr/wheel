import SwiftUI

/// Small dot rendered on the Constellation canvas for each history node.
/// Hover to see full details via the popover in ConstellationCanvas.
struct ConstellationCard: View {
    let node: ConstellationNode

    static let dotSize: CGFloat = 14

    var body: some View {
        Circle()
            .fill(DomainGradient.solidColor(for: node.domain))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
    }
}

/// Floating detail card shown when hovering over a dot
struct ConstellationHoverCard: View {
    let node: ConstellationNode
    var clusterLabel: String?
    var clusterColor: Color?
    var clusterNodeCount: Int?
    var clusterTopDomains: [String]?
    var summary: String?

    private let cardWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            // Domain gradient header
            DomainGradient.placeholderGradient(for: node.domain)
                .frame(width: cardWidth, height: 80)
                .overlay {
                    Text(DomainGradient.initial(for: node.domain))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }

            // Title + favicon bar
            HStack(spacing: 6) {
                FaviconPlaceholder(url: node.url, size: 14, cornerRadius: 3, style: .gradient)

                Text(node.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: cardWidth)
            .background(Color(nsColor: .controlBackgroundColor))

            // Domain label
            HStack {
                Text(node.domain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: cardWidth)
            .background(Color(nsColor: .controlBackgroundColor))

            // Content preview (Wikipedia-style) — only when summary is available
            if let summary = summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: cardWidth)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            // Cluster info row
            if let label = clusterLabel, let color = clusterColor {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let count = clusterNodeCount {
                            Text("· \(count) pages")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    // Top domains in this cluster
                    if let domains = clusterTopDomains, !domains.isEmpty {
                        Text(domains.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: cardWidth)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
    }
}
