import SwiftUI

// MARK: - Mention Chips, Dropdown Panel, and Handling

extension OmniBar {
    var mentionChips: some View {
        HStack(spacing: 4) {
            ForEach(featureModel.mentions) { mention in
                MentionChip(mention: mention) {
                    withAnimation(AppAnimation.standard) {
                        featureModel.removeMention(mention)
                    }
                }
            }
        }
    }

    func mentionDropdownPanel(mentionSuggestionsVM: MentionSuggestionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if mentionSuggestionsVM.suggestions.isEmpty {
                if mentionSuggestionsVM.isSearching {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Searching...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                } else {
                    Text("No matches found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(mentionSuggestionsVM.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            MentionSuggestionRow(
                                suggestion: suggestion,
                                isSelected: index == mentionSuggestionsVM.selectedIndex,
                                onSelect: {
                                    currentMentionProvider?.selectMentionSuggestion(suggestion, in: featureModel)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
}
