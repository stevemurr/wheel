import SwiftUI

/// Named constants for OmniBar input pill layout
private enum OmniBarLayout {
    static let collapsedMinWidth: CGFloat = 280
    static let collapsedMaxWidth: CGFloat = 360
    static let expandedMinWidth: CGFloat = 400
    static let expandedMaxWidth: CGFloat = 540
}

// MARK: - Input Pill, Mode Indicator, Action Button

extension OmniBar {
    // MARK: - Input Pill

    var inputPill: some View {
        HStack(spacing: 8) {
            // Mode indicator icon
            modeIndicator

            // Mention chips (only in chat mode)
            if omniState.mode == .chat {
                mentionChips
            }

            // Input field
            OmniBarTextField(
                text: $omniState.inputText,
                isFocused: $isInputFocused,
                mode: omniState.mode,
                placeholder: omniState.mode == .chat && !omniState.mentions.isEmpty ? "Ask about these pages..." : omniState.placeholder,
                keyboardHandler: self,
                onSubmit: handleSubmit,
                onAtTrigger: { query in
                    handleAtTrigger(query: query)
                },
                onAtDismiss: {
                    if omniState.showMentionDropdown {
                        omniState.dismissMentionDropdown()
                        mentionSuggestionsVM.clear()
                    }
                }
            )

            // Action button (clear in address mode, send in chat mode)
            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            minWidth: shouldExpand ? OmniBarLayout.expandedMinWidth : OmniBarLayout.collapsedMinWidth,
            maxWidth: shouldExpand ? OmniBarLayout.expandedMaxWidth : OmniBarLayout.collapsedMaxWidth
        )
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(
                    color: isInputFocused ? omniState.modeColor.opacity(0.3) : Color.black.opacity(0.15),
                    radius: isInputFocused ? 8 : 4,
                    x: 0,
                    y: 2
                )
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    isInputFocused ? omniState.modeColor.opacity(0.6) : Color.primary.opacity(0.1),
                    lineWidth: isInputFocused ? 2 : 1
                )
        }
    }

    // MARK: - Mode Indicator

    var modeIndicator: some View {
        Button(action: { omniState.nextMode() }) {
            Image(systemName: omniState.modeIcon)
                .foregroundColor(isInputFocused ? omniState.modeColor : .secondary)
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help("Press Tab to switch modes (Address / Chat / Semantic)")
    }

    // MARK: - Action Button

    @ViewBuilder
    var actionButton: some View {
        switch omniState.mode {
        case .address:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    suggestionsVM.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .chat:
            Button(action: handleSubmit) {
                ZStack {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(omniState.inputText.isEmpty ? .secondary : .white)
                    }
                }
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(omniState.inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.purple)
                )
            }
            .buttonStyle(.plain)
            .disabled(omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

        case .semantic:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    semanticSearchVM.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .agent:
            Button(action: handleSubmit) {
                ZStack {
                    if agentEngine.isRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(omniState.inputText.isEmpty ? .secondary : .white)
                    }
                }
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(omniState.inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.green)
                )
            }
            .buttonStyle(.plain)
            .disabled(omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentEngine.isRunning)

        case .readingList:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    readingListVM.loadSavedPages()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .scraping:
            EmptyView() // Scraping mode has no action button
        }
    }
}
