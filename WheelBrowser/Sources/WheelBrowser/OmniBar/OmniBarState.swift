import SwiftUI

/// Represents the current mode of the OmniBar
enum OmniBarMode: Equatable, CaseIterable {
    case address
    case chat
    case semantic
    case agent
    case readingList

    /// SF Symbol icon for this mode
    var icon: String {
        switch self {
        case .address: return "magnifyingglass"
        case .chat: return "sparkles"
        case .semantic: return "brain.head.profile"
        case .agent: return "wand.and.stars"
        case .readingList: return "bookmark.fill"
        }
    }

    /// Placeholder text for the input field in this mode
    var placeholder: String {
        switch self {
        case .address: return "Search or enter URL"
        case .chat: return "Ask about this page..."
        case .semantic: return "Search history semantically..."
        case .agent: return "Describe a task for the agent..."
        case .readingList: return "Search reading list..."
        }
    }

    /// Accent color for this mode
    var color: Color {
        switch self {
        case .address: return .accentColor
        case .chat: return .purple
        case .semantic: return .orange
        case .agent: return .green
        case .readingList: return .pink
        }
    }

    /// The panel visibility value corresponding to this mode
    var correspondingPanel: OmniBarPanelVisibility {
        switch self {
        case .address: return .history
        case .chat: return .chat
        case .semantic: return .semantic
        case .agent: return .agent
        case .readingList: return .readingList
        }
    }
}

/// Represents which panel is currently visible (mutually exclusive)
enum OmniBarPanelVisibility: Equatable {
    case none
    case history
    case chat
    case semantic
    case agent
    case readingList
    case downloads
}

/// Manages the state of the OmniBar
@MainActor
@Observable
class OmniBarState {
    var mode: OmniBarMode = .address
    var inputText: String = ""
    var visiblePanel: OmniBarPanelVisibility = .none

    // MARK: - Mention State
    var mentions: [Mention] = [.currentPage]
    var showMentionDropdown: Bool = false
    var mentionSearchText: String = ""
    private var suppressedAutomaticMention: Mention?

    /// Switch to the next mode (Tab key).
    /// See setMode() for why this must NOT use withAnimation.
    func nextMode() {
        let cases = OmniBarMode.allCases
        guard let currentIndex = cases.firstIndex(of: mode) else { return }
        let nextIndex = cases.index(after: currentIndex)
        mode = nextIndex < cases.endIndex ? cases[nextIndex] : cases[cases.startIndex]
        inputText = ""
    }

    /// Switch to the previous mode (Shift+Tab).
    /// See setMode() for why this must NOT use withAnimation.
    func previousMode() {
        let cases = OmniBarMode.allCases
        guard let currentIndex = cases.firstIndex(of: mode) else { return }
        mode = currentIndex == cases.startIndex ? cases[cases.index(before: cases.endIndex)] : cases[cases.index(before: currentIndex)]
        inputText = ""
    }

    /// Set mode explicitly.
    /// NOTE: Do NOT wrap this in withAnimation — the mode change triggers
    /// onChange(of: omniState.mode) → handleModeChange() which drives panel
    /// transitions via setVisiblePanel()/dismissVisiblePanel(). Adding
    /// withAnimation here creates nested animation contexts that produce a flash.
    func setMode(_ newMode: OmniBarMode) {
        guard mode != newMode else { return }
        mode = newMode
        inputText = ""
    }

    /// Reset state
    func reset() {
        inputText = ""
    }

    // MARK: - Mention Methods

    /// Add a mention to the list
    func addMention(_ mention: Mention) {
        // Don't add duplicates
        guard !mentions.contains(mention) else { return }
        if suppressedAutomaticMention == mention {
            suppressedAutomaticMention = nil
        }
        mentions.append(mention)
    }

    /// Remove a mention from the list
    func removeMention(_ mention: Mention, userInitiated: Bool = true) {
        mentions.removeAll { $0 == mention }
        if userInitiated && mention.isAutomaticDefaultContext {
            suppressedAutomaticMention = mention
        }
    }

    /// Reset mentions to default state, preserving persistent search context mentions (@web, @history, etc.)
    /// - Parameter includeCurrentPage: Whether to include the current page mention. Set to false when on new tab page (no URL).
    func resetMentions(includeCurrentPage: Bool = true) {
        let persistent = mentions.filter { $0.isPersistent }
        guard let automaticMention = automaticMention(includeCurrentPage: includeCurrentPage) else {
            mentions = persistent
            return
        }

        if suppressedAutomaticMention == automaticMention {
            mentions = persistent
        } else {
            mentions = [automaticMention] + persistent
        }
    }

    func clearAutomaticMentionSuppression() {
        suppressedAutomaticMention = nil
    }

    private func automaticMention(includeCurrentPage: Bool) -> Mention? {
        guard includeCurrentPage else { return nil }
        if let mostRecentOverlay = OverlayWindowManager.shared.windows.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return .overlay(
                id: mostRecentOverlay.id,
                title: mostRecentOverlay.title,
                url: mostRecentOverlay.url.absoluteString
            )
        }
        return .currentPage
    }

    /// Open the mention dropdown
    func openMentionDropdown() {
        withAnimation(AppAnimation.standard) {
            showMentionDropdown = true
            mentionSearchText = ""
        }
    }

    /// Dismiss the mention dropdown
    func dismissMentionDropdown() {
        withAnimation(AppAnimation.standard) {
            showMentionDropdown = false
            mentionSearchText = ""
        }
    }

    // MARK: - Panel Visibility

    /// Set the visible panel, dismissing any currently visible panel.
    /// Skips if already showing the requested panel to avoid redundant
    /// withAnimation transactions that cause flash.
    func setVisiblePanel(_ panel: OmniBarPanelVisibility) {
        guard visiblePanel != panel else { return }
        withAnimation(AppAnimation.panelSpring) {
            visiblePanel = panel
        }
    }

    /// Dismiss the currently visible panel.
    /// Skips if already dismissed to avoid redundant animation transactions.
    func dismissVisiblePanel() {
        guard visiblePanel != .none else { return }
        withAnimation(AppAnimation.panelSpring) {
            visiblePanel = .none
        }
    }

    /// Check if a panel is visible for the given mode
    func isPanelVisible(for mode: OmniBarMode) -> Bool {
        visiblePanel == mode.correspondingPanel && self.mode == mode
    }

    // MARK: - Pass-through Accessors

    var modeIcon: String { mode.icon }
    var placeholder: String { mode.placeholder }
    var modeColor: Color { mode.color }
}
