import SwiftUI

// MARK: - Suggestion Row (handles both open tabs and history)

struct SuggestionRow: View {
    let suggestion: Suggestion
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

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
                    highlightedText(title, matchedIndices: suggestion.titleMatches)
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

                highlightedText(displayURL, matchedIndices: displayURLMatchIndices)
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
                        .fill(colorForDomain(domain))
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
            // Show "Switch" action hint for open tabs
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
            // Show time for history entries
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

    /// Adjust URL match indices to account for scheme/www stripping in display URL
    private var displayURLMatchIndices: [Int] {
        let rawURL = suggestion.url
        let indices = suggestion.urlMatches
        guard !indices.isEmpty else { return [] }

        // Calculate how many characters were stripped from the front
        var stripped = 0
        if rawURL.hasPrefix("https://") {
            stripped = 8
        } else if rawURL.hasPrefix("http://") {
            stripped = 7
        }
        // Account for www. removal (only if it follows the scheme)
        let afterScheme = rawURL.dropFirst(stripped)
        if afterScheme.hasPrefix("www.") {
            stripped += 4
        }

        return indices.compactMap { idx in
            let adjusted = idx - stripped
            return adjusted >= 0 ? adjusted : nil
        }
    }

    private func highlightedText(_ string: String, matchedIndices: [Int]) -> Text {
        guard !matchedIndices.isEmpty else {
            return Text(string).foregroundColor(.primary)
        }
        let indexSet = Set(matchedIndices)
        var result = Text("")
        for (i, char) in string.enumerated() {
            if indexSet.contains(i) {
                result = result + Text(String(char)).bold().foregroundColor(.primary)
            } else {
                result = result + Text(String(char)).foregroundColor(.secondary)
            }
        }
        return result
    }

    private var relativeTimeString: String? {
        // Only for history entries
        guard case .history(let entry, _, _, _) = suggestion else { return nil }
        return entry.timestamp.relativeTimeString()
    }

    private func colorForDomain(_ domain: String) -> Color {
        DomainColor.color(for: domain)
    }
}
