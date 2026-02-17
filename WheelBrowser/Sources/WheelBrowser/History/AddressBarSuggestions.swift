import SwiftUI

/// View model for managing address bar suggestions
@MainActor
class SuggestionsViewModel: ObservableObject {
    @Published var suggestions: [HistoryEntry] = []
    @Published var selectedIndex: Int = -1
    @Published var isVisible: Bool = false

    private let history = BrowsingHistory.shared
    private var searchTask: Task<Void, Never>?

    /// Update suggestions based on user input
    func updateSuggestions(for query: String) {
        // Cancel any pending search
        searchTask?.cancel()

        guard !query.isEmpty else {
            suggestions = []
            selectedIndex = -1
            isVisible = false
            return
        }

        // Debounce the search for performance
        searchTask = Task {
            // Small delay to debounce rapid typing
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            guard !Task.isCancelled else { return }

            let results = history.search(query: query, limit: 8)

            guard !Task.isCancelled else { return }

            suggestions = results
            selectedIndex = -1
            isVisible = !results.isEmpty
        }
    }

    /// Select the next suggestion (down arrow)
    /// Since suggestions are displayed in reverse order (best at bottom),
    /// down arrow moves towards better matches (lower indices)
    func selectNext() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex == -1 {
            // Start from the best match (index 0, displayed at bottom)
            selectedIndex = 0
        } else if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = suggestions.count - 1 // Wrap to top of visual list
        }
    }

    /// Select the previous suggestion (up arrow)
    /// Since suggestions are displayed in reverse order (best at bottom),
    /// up arrow moves towards worse matches (higher indices)
    func selectPrevious() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex == -1 {
            // Start from the worst match (last index, displayed at top)
            selectedIndex = suggestions.count - 1
        } else if selectedIndex < suggestions.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0 // Wrap to bottom of visual list
        }
    }

    /// Get the currently selected suggestion, if any
    var selectedSuggestion: HistoryEntry? {
        guard selectedIndex >= 0 && selectedIndex < suggestions.count else { return nil }
        return suggestions[selectedIndex]
    }

    /// Hide suggestions
    func hide() {
        isVisible = false
        selectedIndex = -1
    }

    /// Clear all suggestions
    func clear() {
        suggestions = []
        selectedIndex = -1
        isVisible = false
    }
}

/// Dropdown view displaying address bar suggestions
/// Note: Since this appears ABOVE the URL bar, suggestions are displayed in reverse order
/// so the best match (index 0) appears closest to the URL bar (at the bottom of the dropdown)
struct AddressBarSuggestions: View {
    @ObservedObject var viewModel: SuggestionsViewModel
    let onSelect: (HistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Display in reverse order: best match at bottom (closest to URL bar)
            ForEach(Array(viewModel.suggestions.enumerated().reversed()), id: \.element.id) { index, entry in
                SuggestionRow(
                    entry: entry,
                    isSelected: index == viewModel.selectedIndex,
                    onSelect: {
                        onSelect(entry)
                    }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Individual suggestion row
struct SuggestionRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    private var domain: String {
        if let url = URL(string: entry.url), let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 10) {
            // Favicon placeholder
            faviconView
                .frame(width: 20, height: 20)

            // Title and URL
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(displayURL)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time indicator for recent visits
            if let timeAgo = relativeTimeString {
                Text(timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color.clear
    }

    @ViewBuilder
    private var faviconView: some View {
        if !domain.isEmpty {
            let initial = String(domain.prefix(1)).uppercased()
            Text(initial)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorForDomain(domain))
                )
        } else {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    private var displayURL: String {
        // Show a cleaned up URL
        var url = entry.url
        url = url.replacingOccurrences(of: "https://", with: "")
        url = url.replacingOccurrences(of: "http://", with: "")
        url = url.replacingOccurrences(of: "www.", with: "")
        // Truncate if too long
        if url.count > 60 {
            url = String(url.prefix(57)) + "..."
        }
        return url
    }

    private var relativeTimeString: String? {
        let interval = Date().timeIntervalSince(entry.timestamp)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else {
            return nil // Don't show for older entries
        }
    }

    private func colorForDomain(_ domain: String) -> Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
        ]
        let hash = domain.utf8.reduce(0) { $0 &+ Int($1) }
        return colors[abs(hash) % colors.count]
    }
}
