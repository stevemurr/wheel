import SwiftUI
import AppKit

/// A floating overlay window that displays web content
struct OverlayWindow: View {
    var item: OverlayWindowItem
    let containerSize: CGSize
    let onClose: () -> Void
    let onBringToFront: () -> Void
    let onOpenInTab: () -> Void
    let onMinimize: () -> Void
    let onToggleMaximize: () -> Void
    let onUpdatePosition: (CGPoint) -> Void
    let onUpdateSize: (CGSize) -> Void

    @State private var isHoveringOpenInTab = false
    @State private var isHoveringReaderMode = false
    @State private var isHoveringSaveButton = false
    @State private var isHoveringCopyURL = false
    @State private var isLoading = true
    @State private var isReaderMode = false
    @State private var isSavedToReadingList = false

    var body: some View {
        FloatingWindowShell(
            item: item,
            containerSize: containerSize,
            onClose: onClose,
            onBringToFront: onBringToFront,
            onMinimize: onMinimize,
            onToggleMaximize: onToggleMaximize,
            onUpdatePosition: onUpdatePosition,
            onUpdateSize: onUpdateSize
        ) {
            readerModeButton
            saveToReadingListButton
            copyURLButton
            openInTabButton
        } content: {
            ZStack {
                OverlayWebView(url: item.url, item: item, isLoading: $isLoading, isReaderMode: $isReaderMode)
                    .id(item.webViewRevision)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                }
            }
        }
    }

    // MARK: - Reader Mode Button

    private var readerModeButton: some View {
        Button {
            withAnimation(AppAnimation.medium) {
                isReaderMode.toggle()
            }
        } label: {
            Image(systemName: isReaderMode ? "doc.richtext.fill" : "doc.richtext")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isReaderMode ? .accentColor : (isHoveringReaderMode ? .accentColor : .secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isReaderMode ? Color.accentColor.opacity(0.2) : (isHoveringReaderMode ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHoveringReaderMode = hovering
            }
        }
        .help(isReaderMode ? "Exit reader mode" : "Reader mode")
    }

    // MARK: - Save to Reading List Button

    private var saveToReadingListButton: some View {
        Button {
            toggleSaveToReadingList()
        } label: {
            Image(systemName: isSavedToReadingList ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSavedToReadingList ? .pink : (isHoveringSaveButton ? .pink : .secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSavedToReadingList ? Color.pink.opacity(0.2) : (isHoveringSaveButton ? Color.pink.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHoveringSaveButton = hovering
            }
        }
        .help(isSavedToReadingList ? "Remove from reading list" : "Save to reading list")
        .onAppear {
            checkIfSaved()
        }
    }

    private func toggleSaveToReadingList() {
        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let newState = try await database.toggleSaved(url: item.url.absoluteString, title: item.title)

                await MainActor.run {
                    withAnimation(AppAnimation.medium) {
                        isSavedToReadingList = newState
                    }
                }

                // Generate summary in background if page was saved
                if newState {
                    Task.detached {
                        await SummaryGenerator.shared.backfillSummaries()
                    }
                }
            } catch {
                Log.Overlay.error("Failed to toggle save state", error: error)
            }
        }
    }

    private func checkIfSaved() {
        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let saved = try await database.isSaved(url: item.url.absoluteString)

                await MainActor.run {
                    isSavedToReadingList = saved
                }
            } catch {
                Log.Overlay.error("Failed to check saved state", error: error)
            }
        }
    }

    // MARK: - Copy URL Button

    private var copyURLButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHoveringCopyURL ? .accentColor : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringCopyURL ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHoveringCopyURL = hovering
            }
        }
        .help("Copy URL")
    }

    // MARK: - Open in Tab Button

    private var openInTabButton: some View {
        Button(action: onOpenInTab) {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHoveringOpenInTab ? .accentColor : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringOpenInTab ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHoveringOpenInTab = hovering
            }
        }
        .help("Open in new tab")
    }

}
