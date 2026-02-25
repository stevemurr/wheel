import SwiftUI

/// Debug tools widget providing quick access to maintenance utilities
@MainActor
final class DebugWidget: Widget, ObservableObject {
    static let typeIdentifier = "debug"
    static let displayName = "Debug Tools"
    static let iconName = "wrench.and.screwdriver"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large]
    }

    init() {}

    @ViewBuilder
    func makeContent() -> some View {
        DebugWidgetView(size: currentSize)
    }

    func refresh() async {
        // No data to refresh
    }
}

struct DebugWidgetView: View {
    let size: WidgetSize

    @State private var showClearHistoryAlert = false
    @State private var showClearReadingListAlert = false
    @State private var showClearSemanticIndexAlert = false
    @State private var statusMessage: String?
    @State private var isProcessing = false

    var body: some View {
        Group {
            switch size {
            case .small:
                smallView
            case .medium:
                mediumView
            case .large, .wide, .extraLarge:
                largeView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .small ? .center : .topLeading)
        .alert("Clear Browsing History", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearBrowsingHistory()
            }
        } message: {
            Text("This will permanently delete all browsing history. This action cannot be undone.")
        }
        .alert("Clear Reading List", isPresented: $showClearReadingListAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearReadingList()
            }
        } message: {
            Text("This will remove all items from your reading list. This action cannot be undone.")
        }
        .alert("Clear Semantic Index", isPresented: $showClearSemanticIndexAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearSemanticIndex()
            }
        } message: {
            Text("This will delete all indexed page data. This action cannot be undone.")
        }
    }

    // MARK: - Small View (Icon + Title only)

    private var smallView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Debug")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Medium View (Compact buttons)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)

                Text("Debug Tools")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            // Compact button row
            HStack(spacing: 8) {
                compactButton(
                    icon: "clock.arrow.circlepath",
                    label: "History",
                    color: .blue
                ) {
                    showClearHistoryAlert = true
                }

                compactButton(
                    icon: "bookmark.slash",
                    label: "Reading List",
                    color: .purple
                ) {
                    showClearReadingListAlert = true
                }

                compactButton(
                    icon: "magnifyingglass.circle",
                    label: "Index",
                    color: .green
                ) {
                    showClearSemanticIndexAlert = true
                }
            }

            if let message = statusMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Large View (Full buttons with descriptions)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)

                Text("Debug Tools")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            // Full action buttons
            VStack(spacing: 10) {
                actionButton(
                    icon: "clock.arrow.circlepath",
                    title: "Clear Browsing History",
                    description: "Remove all browsing history entries",
                    color: .blue
                ) {
                    showClearHistoryAlert = true
                }

                actionButton(
                    icon: "bookmark.slash",
                    title: "Clear Reading List",
                    description: "Remove all saved reading list items",
                    color: .purple
                ) {
                    showClearReadingListAlert = true
                }

                actionButton(
                    icon: "magnifyingglass.circle",
                    title: "Clear Semantic Index",
                    description: "Delete all indexed page data",
                    color: .green
                ) {
                    showClearSemanticIndexAlert = true
                }
            }

            Spacer(minLength: 0)

            if let message = statusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Button Components

    private func compactButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    private func actionButton(
        icon: String,
        title: String,
        description: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Actions

    private func clearBrowsingHistory() {
        isProcessing = true
        BrowsingHistory.shared.clearHistory()
        showStatus("Browsing history cleared")
    }

    private func clearReadingList() {
        isProcessing = true
        Task {
            do {
                let db = try SearchDatabase()
                try await db.initialize()
                try await db.clearReadingList()
                await MainActor.run {
                    showStatus("Reading list cleared")
                }
            } catch {
                await MainActor.run {
                    showStatus("Failed to clear reading list")
                }
            }
        }
    }

    private func clearSemanticIndex() {
        isProcessing = true
        Task {
            do {
                let db = try SearchDatabase()
                try await db.initialize()
                try await db.clearAllData()
                await MainActor.run {
                    showStatus("Semantic index cleared")
                }
            } catch {
                await MainActor.run {
                    showStatus("Failed to clear semantic index")
                }
            }
        }
    }

    private func showStatus(_ message: String) {
        withAnimation {
            statusMessage = message
            isProcessing = false
        }

        // Clear status after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation {
                    statusMessage = nil
                }
            }
        }
    }
}

#Preview("Small") {
    DebugWidgetView(size: .small)
        .frame(width: 150, height: 150)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Medium") {
    DebugWidgetView(size: .medium)
        .frame(width: 300, height: 150)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Large") {
    DebugWidgetView(size: .large)
        .frame(width: 300, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
