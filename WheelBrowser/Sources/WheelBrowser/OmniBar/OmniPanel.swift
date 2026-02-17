import SwiftUI

/// A reusable panel that appears above the OmniBar for different modes
struct OmniPanel<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let subtitle: String?
    let menuContent: (() -> AnyView)?
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    private let maxHeight: CGFloat = 400
    private let maxWidth: CGFloat = 700

    init(
        title: String,
        icon: String,
        iconColor: Color = .accentColor,
        subtitle: String? = nil,
        menuContent: (() -> AnyView)? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.subtitle = subtitle
        self.menuContent = menuContent
        self.onDismiss = onDismiss
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .opacity(0.5)

            // Content area
            content()
        }
        .frame(maxWidth: maxWidth)
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: -8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(iconColor)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let menuContent = menuContent {
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .separatorColor).opacity(0.05))
    }
}

// MARK: - Empty State View (reusable)

struct OmniPanelEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - History Panel using OmniPanel

struct HistoryPanelContent: View {
    @ObservedObject var viewModel: SuggestionsViewModel
    let searchText: String
    let onSelect: (HistoryEntry) -> Void

    private let history = BrowsingHistory.shared

    var body: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if viewModel.suggestions.isEmpty && searchText.isEmpty {
                    // Show recent history when no search
                    let recentHistory = Array(history.entries.prefix(20))
                    if recentHistory.isEmpty {
                        OmniPanelEmptyState(
                            icon: "clock",
                            title: "No browsing history",
                            subtitle: "Pages you visit will appear here"
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(Array(recentHistory.enumerated()), id: \.element.id) { index, entry in
                            HistoryRow(
                                entry: entry,
                                isSelected: index == viewModel.selectedIndex,
                                onSelect: { onSelect(entry) }
                            )
                        }
                    }
                } else if viewModel.suggestions.isEmpty {
                    // No search results
                    OmniPanelEmptyState(
                        icon: "magnifyingglass",
                        title: "No matches found",
                        subtitle: "Try a different search term"
                    )
                    .padding(.top, 30)
                } else {
                    // Show search results
                    ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, entry in
                        HistoryRow(
                            entry: entry,
                            isSelected: index == viewModel.selectedIndex,
                            onSelect: { onSelect(entry) }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    var subtitle: String {
        if !searchText.isEmpty {
            return "\(viewModel.suggestions.count) results"
        }
        return "Recent"
    }
}

// MARK: - Chat Panel using OmniPanel

struct ChatPanelContent: View {
    @ObservedObject var agentManager: AgentManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    if agentManager.messages.isEmpty {
                        OmniPanelEmptyState(
                            icon: "bubble.left.and.bubble.right",
                            title: "Start a conversation",
                            subtitle: "Ask questions about the current page"
                        )
                        .padding(.top, 30)

                        if let error = agentManager.error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)

                            Button("Retry") {
                                Task { await agentManager.initialize() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        ForEach(agentManager.messages) { message in
                            ChatPanelMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: agentManager.messages.count) { _, _ in
                if let lastMessage = agentManager.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    var subtitle: String? {
        if agentManager.isLoading {
            return "Thinking..."
        }
        return nil
    }
}

// MARK: - History Row

struct HistoryRow: View {
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
        HStack(spacing: 12) {
            // Favicon
            faviconView
                .frame(width: 28, height: 28)

            // Title and URL
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? domain : entry.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(displayURL)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time indicator
            if let timeAgo = relativeTimeString {
                Text(timeAgo)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorForDomain(domain))
                )
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    private var displayURL: String {
        var url = entry.url
        url = url.replacingOccurrences(of: "https://", with: "")
        url = url.replacingOccurrences(of: "http://", with: "")
        url = url.replacingOccurrences(of: "www.", with: "")
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
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: entry.timestamp)
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
