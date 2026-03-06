import SwiftUI

/// Horizontal row of tappable follow-up suggestion pills after the last assistant message.
struct FollowUpSuggestionsView: View {
    let suggestions: [String]
    var onSelect: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Continue with")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: { onSelect(suggestion) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.8))

                                    Text(suggestion)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundColor(.primary.opacity(0.84))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
