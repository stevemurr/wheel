import SwiftUI

// MARK: - Mention Chips, Dropdown Panel, and Handling

extension OmniBar {
    // MARK: - Mention Chips

    var mentionChips: some View {
        HStack(spacing: 4) {
            ForEach(omniState.mentions) { mention in
                MentionChip(mention: mention) {
                    withAnimation(AppAnimation.standard) {
                        omniState.removeMention(mention)
                    }
                }
            }
        }
    }

    // MARK: - Mention Dropdown Panel

    var mentionDropdownPanel: some View {
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
                                    selectMentionSuggestion(suggestion)
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

    // MARK: - Mention Handling

    func handleAtTrigger(query: String) {
        if !omniState.showMentionDropdown {
            omniState.openMentionDropdown()
        }
        omniState.mentionSearchText = query
        mentionSuggestionsVM.updateSuggestions(
            for: query,
            excluding: omniState.mentions,
            currentTabId: tab.id
        )
    }

    func handleMentionSelection() {
        guard let suggestion = mentionSuggestionsVM.selectedSuggestion else { return }
        selectMentionSuggestion(suggestion)
    }

    func selectMentionSuggestion(_ suggestion: MentionSuggestion) {
        withAnimation(AppAnimation.standard) {
            omniState.addMention(suggestion.mention)
            omniState.dismissMentionDropdown()
        }
        mentionSuggestionsVM.clear()

        // Remove the @query from input text
        removeAtQueryFromInput()
    }

    func removeAtQueryFromInput() {
        // Find and remove @... pattern from input
        let text = omniState.inputText
        if let atIndex = text.lastIndex(of: "@") {
            omniState.inputText = String(text[..<atIndex])
        }
    }
}
