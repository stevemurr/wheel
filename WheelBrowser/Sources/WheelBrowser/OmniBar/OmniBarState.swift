import SwiftUI
import Combine

/// Represents the current mode of the OmniBar
enum OmniBarMode: Equatable {
    case address
    case chat
    case semantic
    case agent
    case readingList
    case scraping
}

/// Represents which panel is currently visible (mutually exclusive)
enum OmniBarPanelVisibility: Equatable {
    case none
    case history
    case chat
    case semantic
    case agent
    case readingList
    case scraping
    case downloads
}

/// Manages the state of the OmniBar
@MainActor
class OmniBarState: ObservableObject {
    @Published var mode: OmniBarMode = .address
    @Published var inputText: String = ""
    @Published var isFocused: Bool = false
    @Published var visiblePanel: OmniBarPanelVisibility = .none

    // Backwards-compatible computed accessors
    var showChatPanel: Bool { visiblePanel == .chat }
    var showHistoryPanel: Bool { visiblePanel == .history }
    var showSemanticPanel: Bool { visiblePanel == .semantic }
    var showAgentPanel: Bool { visiblePanel == .agent }
    var showReadingListPanel: Bool { visiblePanel == .readingList }
    var showScrapingPanel: Bool { visiblePanel == .scraping }

    // MARK: - Mention State
    @Published var mentions: [Mention] = [.currentPage]
    @Published var showMentionDropdown: Bool = false
    @Published var mentionSearchText: String = ""

    /// Switch to the next mode (Tab key)
    func nextMode() {
        withAnimation(AppAnimation.standard) {
            switch mode {
            case .address:
                mode = .chat
                inputText = ""
            case .chat:
                mode = .semantic
                inputText = ""
            case .semantic:
                mode = .agent
                inputText = ""
            case .agent:
                mode = .readingList
                inputText = ""
            case .readingList:
                mode = .scraping
                inputText = ""
            case .scraping:
                mode = .address
                inputText = ""
            }
        }
    }

    /// Switch to the previous mode (Shift+Tab)
    func previousMode() {
        withAnimation(AppAnimation.standard) {
            switch mode {
            case .address:
                mode = .scraping
                inputText = ""
            case .chat:
                mode = .address
                inputText = ""
            case .semantic:
                mode = .chat
                inputText = ""
            case .agent:
                mode = .semantic
                inputText = ""
            case .readingList:
                mode = .agent
                inputText = ""
            case .scraping:
                mode = .readingList
                inputText = ""
            }
        }
    }

    /// Set mode explicitly
    func setMode(_ newMode: OmniBarMode) {
        guard mode != newMode else { return }
        withAnimation(AppAnimation.standard) {
            mode = newMode
            inputText = ""
        }
    }

    /// Reset state
    func reset() {
        inputText = ""
        isFocused = false
    }

    // MARK: - Mention Methods

    /// Add a mention to the list
    func addMention(_ mention: Mention) {
        // Don't add duplicates
        guard !mentions.contains(mention) else { return }
        mentions.append(mention)
    }

    /// Remove a mention from the list
    func removeMention(_ mention: Mention) {
        mentions.removeAll { $0 == mention }
    }

    /// Reset mentions to default state, preserving persistent search context mentions (@web, @history, etc.)
    /// - Parameter includeCurrentPage: Whether to include the current page mention. Set to false when on new tab page (no URL).
    func resetMentions(includeCurrentPage: Bool = true) {
        let persistent = mentions.filter { $0.isPersistent }
        if includeCurrentPage {
            // If overlay windows are open, use the most recent one as default instead of current page
            if let mostRecentOverlay = OverlayWindowManager.shared.windows.sorted(by: { $0.createdAt > $1.createdAt }).first {
                mentions = [.overlay(
                    id: mostRecentOverlay.id,
                    title: mostRecentOverlay.title,
                    url: mostRecentOverlay.url.absoluteString
                )] + persistent
            } else {
                mentions = [.currentPage] + persistent
            }
        } else {
            mentions = persistent
        }
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

    /// Set the visible panel, dismissing any currently visible panel
    func setVisiblePanel(_ panel: OmniBarPanelVisibility) {
        withAnimation(AppAnimation.panelSpring) {
            visiblePanel = panel
        }
    }

    /// Dismiss the currently visible panel
    func dismissVisiblePanel() {
        withAnimation(AppAnimation.panelSpring) {
            visiblePanel = .none
        }
    }

    // MARK: - Legacy Panel Methods (delegate to setVisiblePanel/dismissVisiblePanel)

    func dismissChatPanel() { dismissVisiblePanel() }
    func openChatPanel() { setVisiblePanel(.chat) }

    func dismissHistoryPanel() { dismissVisiblePanel() }
    func openHistoryPanel() { setVisiblePanel(.history) }

    func dismissSemanticPanel() { dismissVisiblePanel() }
    func openSemanticPanel() { setVisiblePanel(.semantic) }

    func dismissAgentPanel() { dismissVisiblePanel() }
    func openAgentPanel() { setVisiblePanel(.agent) }

    func dismissReadingListPanel() { dismissVisiblePanel() }
    func openReadingListPanel() { setVisiblePanel(.readingList) }

    func dismissScrapingPanel() { dismissVisiblePanel() }
    func openScrapingPanel() { setVisiblePanel(.scraping) }

    /// Check if a panel is visible for the given mode
    func isPanelVisible(for mode: OmniBarMode) -> Bool {
        switch mode {
        case .address:
            return visiblePanel == .history && self.mode == .address
        case .chat:
            return visiblePanel == .chat && self.mode == .chat
        case .semantic:
            return visiblePanel == .semantic && self.mode == .semantic
        case .agent:
            return visiblePanel == .agent && self.mode == .agent
        case .readingList:
            return visiblePanel == .readingList && self.mode == .readingList
        case .scraping:
            return visiblePanel == .scraping && self.mode == .scraping
        }
    }

    /// Icon for the current mode
    var modeIcon: String {
        switch mode {
        case .address:
            return "magnifyingglass"
        case .chat:
            return "sparkles"
        case .semantic:
            return "brain.head.profile"
        case .agent:
            return "wand.and.stars"
        case .readingList:
            return "bookmark.fill"
        case .scraping:
            return "network"
        }
    }

    /// Placeholder text for the current mode
    var placeholder: String {
        switch mode {
        case .address:
            return "Search or enter URL"
        case .chat:
            return "Ask about this page..."
        case .semantic:
            return "Search history semantically..."
        case .agent:
            return "Describe a task for the agent..."
        case .readingList:
            return "Search reading list..."
        case .scraping:
            return "Scraping jobs..."
        }
    }

    /// Accent color for the current mode
    var modeColor: Color {
        switch mode {
        case .address:
            return .accentColor
        case .chat:
            return .purple
        case .semantic:
            return .orange
        case .agent:
            return .green
        case .readingList:
            return .pink
        case .scraping:
            return .cyan
        }
    }
}
