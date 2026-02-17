import SwiftUI
import Combine

/// Represents the current mode of the OmniBar
enum OmniBarMode: Equatable {
    case address
    case chat
}

/// Manages the state of the OmniBar
@MainActor
class OmniBarState: ObservableObject {
    @Published var mode: OmniBarMode = .address
    @Published var inputText: String = ""
    @Published var isFocused: Bool = false
    @Published var showChatPanel: Bool = false
    @Published var showHistoryPanel: Bool = false

    /// Switch to the next mode (Tab key)
    func nextMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch mode {
            case .address:
                mode = .chat
                inputText = ""
            case .chat:
                mode = .address
                inputText = ""
            }
        }
    }

    /// Switch to the previous mode (Shift+Tab)
    func previousMode() {
        nextMode() // Same as next since we only have 2 modes
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
        }
    }

    /// Icon for the current mode
    var modeIcon: String {
        switch mode {
        case .address:
            return "magnifyingglass"
        case .chat:
            return "sparkles"
        }
    }

    /// Placeholder text for the current mode
    var placeholder: String {
        switch mode {
        case .address:
            return "Search or enter URL"
        case .chat:
            return "Ask about this page..."
        }
    }

    /// Accent color for the current mode
    var modeColor: Color {
        switch mode {
        case .address:
            return .accentColor
        case .chat:
            return .purple
        }
    }
}
