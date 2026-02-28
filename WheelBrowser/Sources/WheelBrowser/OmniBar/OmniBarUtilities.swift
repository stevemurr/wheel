import SwiftUI

// MARK: - Page Save Logic

extension OmniBar {
    func toggleSaveCurrentPage() {
        guard let url = tab.url else { return }
        let title = tab.title

        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let isSaved = try await database.toggleSaved(url: url.absoluteString, title: title)

                // Show brief visual feedback
                await MainActor.run {
                    // Post notification for potential visual feedback
                    NotificationCenter.default.post(
                        name: Notification.Name("pageSaveStateChanged"),
                        object: nil,
                        userInfo: ["url": url.absoluteString, "isSaved": isSaved]
                    )
                }

                Log.OmniBar.info("Page \(isSaved ? "saved to" : "removed from") reading list: \(url.absoluteString)")

                // Generate summary in background if page was saved
                if isSaved {
                    Task.detached {
                        await SummaryGenerator.shared.backfillSummaries()
                    }
                }
            } catch {
                Log.OmniBar.error("Failed to toggle save state", error: error)
            }
        }
    }

    func checkIfCurrentPageIsSaved() async {
        guard let url = tab.url else {
            await MainActor.run {
                isCurrentPageSaved = false
            }
            return
        }

        do {
            let database = SearchDatabase.shared
            try await database.initialize()
            let saved = try await database.isSaved(url: url.absoluteString)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCurrentPageSaved = saved
                }
            }
        } catch {
            Log.OmniBar.error("Failed to check save state", error: error)
            await MainActor.run {
                isCurrentPageSaved = false
            }
        }
    }
}

// MARK: - Navigation Button

struct NavigationButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - OmniBar Find Bar

struct OmniBarFindBar: View {
    @ObservedObject var tab: Tab
    @Binding var findText: String
    @FocusState var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11, weight: .medium))

                    TextField("Find in page", text: $findText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isFocused)
                        .onChange(of: findText) { _, newValue in
                            tab.findInPage(newValue)
                        }
                        .onSubmit {
                            tab.findNext()
                        }

                    if !findText.isEmpty {
                        Button(action: { findText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 220)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                }

                HStack(spacing: 4) {
                    Button(action: { tab.findPrevious() }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(findText.isEmpty ? .secondary.opacity(0.5) : .primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.clear)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findText.isEmpty)

                    Button(action: { tab.findNext() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(findText.isEmpty ? .secondary.opacity(0.5) : .primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.clear)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findText.isEmpty)
                }

                Button(action: {
                    tab.hideFindBar()
                    findText = ""
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle()
                                .fill(Color.clear)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()
        }
    }
}
