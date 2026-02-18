import SwiftUI
import Combine

/// Represents the current mode of the OmniBar
enum OmniBarMode: Equatable {
    case address
    case chat
    case semantic
}

/// Manages the state of the OmniBar
@MainActor
class OmniBarState: ObservableObject {
    @Published var mode: OmniBarMode = .address
    @Published var inputText: String = ""
    @Published var isFocused: Bool = false
    @Published var showChatPanel: Bool = false
    @Published var showHistoryPanel: Bool = false
    @Published var showSemanticPanel: Bool = false

    // MARK: - Mention State
    @Published var mentions: [Mention] = [.currentPage]
    @Published var showMentionDropdown: Bool = false
    @Published var mentionSearchText: String = ""

    /// Switch to the next mode (Tab key)
    func nextMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch mode {
            case .address:
                mode = .chat
                inputText = ""
            case .chat:
                mode = .semantic
                inputText = ""
            case .semantic:
                mode = .address
                inputText = ""
            }
        }
    }

    /// Switch to the previous mode (Shift+Tab)
    func previousMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch mode {
            case .address:
                mode = .semantic
                inputText = ""
            case .chat:
                mode = .address
                inputText = ""
            case .semantic:
                mode = .chat
                inputText = ""
            }
        }
    }

    /// Set mode explicitly
    func setMode(_ newMode: OmniBarMode) {
        guard mode != newMode else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
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

    /// Reset mentions to default state (current page only)
    func resetMentions() {
        mentions = [.currentPage]
    }

    /// Open the mention dropdown
    func openMentionDropdown() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showMentionDropdown = true
            mentionSearchText = ""
        }
    }

    /// Dismiss the mention dropdown
    func dismissMentionDropdown() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showMentionDropdown = false
            mentionSearchText = ""
        }
    }

    /// Dismiss chat panel
    func dismissChatPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showChatPanel = false
        }
    }

    /// Show chat panel
    func openChatPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showChatPanel = true
            showHistoryPanel = false
            showSemanticPanel = false
        }
    }

    /// Dismiss history panel
    func dismissHistoryPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showHistoryPanel = false
        }
    }

    /// Show history panel
    func openHistoryPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showHistoryPanel = true
            showChatPanel = false
            showSemanticPanel = false
        }
    }

    /// Dismiss semantic panel
    func dismissSemanticPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showSemanticPanel = false
        }
    }

    /// Show semantic panel
    func openSemanticPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showSemanticPanel = true
            showHistoryPanel = false
            showChatPanel = false
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
        }
    }
}
