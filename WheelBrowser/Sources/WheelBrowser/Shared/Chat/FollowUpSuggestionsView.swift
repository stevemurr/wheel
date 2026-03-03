import SwiftUI

/// Horizontal row of tappable follow-up suggestion pills after the last assistant message.
struct FollowUpSuggestionsView: View {
    let suggestions: [String]
    var onSelect: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(action: { onSelect(suggestion) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.purple.opacity(0.7))

                                Text(suggestion)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
