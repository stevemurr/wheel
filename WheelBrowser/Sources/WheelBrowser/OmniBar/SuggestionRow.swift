import SwiftUI

// MARK: - Suggestion Row (handles both open tabs and history)

struct SuggestionRow: View, Equatable {
    let suggestion: Suggestion
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    static func == (lhs: SuggestionRow, rhs: SuggestionRow) -> Bool {
        lhs.suggestion.id == rhs.suggestion.id && lhs.isSelected == rhs.isSelected
    }

    private var domain: String {
        suggestion.url.urlCleanDomain
    }

    private var title: String {
        suggestion.title.isEmpty ? domain : suggestion.title
    }

    var body: some View {
        HStack(spacing: 12) {
            // Favicon / Tab indicator
            faviconView
                .frame(width: 28, height: 28)

            // Title and URL
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    HighlightedTextBuilder.fromIndices(title, indices: suggestion.titleMatches)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    // Open tab badge
                    if suggestion.isOpenTab {
                        Text("Tab")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green)
                            )
                    }
                }

                HighlightedTextBuilder.fromIndices(displayURL, indices: displayURLMatchIndices)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }

            Spacer()

            // Right side indicator
            rightIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.35)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color.clear
    }

    @ViewBuilder
    private var faviconView: some View {
        if suggestion.isOpenTab {
            // Show a tab icon for open tabs
            Image(systemName: "square.on.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.15))
                )
        } else if !domain.isEmpty {
            let initial = String(domain.prefix(1)).uppercased()
            Text(initial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DomainColor.color(for: domain))
                )
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    @ViewBuilder
    private var rightIndicator: some View {
        if suggestion.isOpenTab {
            Text("Switch")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.1))
                )
        } else if let timeAgo = relativeTimeString {
            Text(timeAgo)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
        }
    }

    private var displayURL: String {
        URLFormatter.shared.displayURL(suggestion.url)
    }

    /// Adjust URL match indices to account for scheme/www stripping in display URL.
    /// Derives the offset by finding the display URL within the raw URL (single source of truth).
    private var displayURLMatchIndices: [Int] {
        let rawURL = suggestion.url
        let indices = suggestion.urlMatches
        guard !indices.isEmpty else { return [] }

        // Derive the offset by finding where the display URL starts in the raw URL
        let display = displayURL
        let stripped: Int
        if let range = rawURL.range(of: display) {
            stripped = rawURL.distance(from: rawURL.startIndex, to: range.lowerBound)
        } else {
            // Fallback: calculate based on known scheme patterns
            var offset = 0
            if rawURL.hasPrefix("https://") {
                offset = 8
            } else if rawURL.hasPrefix("http://") {
                offset = 7
            }
            let afterScheme = rawURL.dropFirst(offset)
            if afterScheme.hasPrefix("www.") {
                offset += 4
            }
            stripped = offset
        }

        return indices.compactMap { idx in
            let adjusted = idx - stripped
            return adjusted >= 0 ? adjusted : nil
        }
    }

    private var relativeTimeString: String? {
        guard case .history(let entry, _, _, _) = suggestion else { return nil }
        return entry.timestamp.relativeTimeString()
    }
}
