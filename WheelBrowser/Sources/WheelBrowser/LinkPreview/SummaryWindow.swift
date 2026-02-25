import SwiftUI
import AppKit

/// A mini window-style panel that displays a link summary with action buttons
struct SummaryWindow: View {
    @ObservedObject var state: LinkPreviewState
    let containerSize: CGSize
    let onClose: () -> Void
    let onSaveToReadingList: () -> Void
    let onCopyURL: () -> Void
    let onOpenInTab: () -> Void

    // Constants matching OverlayWindow
    private let cornerRadius: CGFloat = 12
    private let titleBarHeight: CGFloat = 36
    private let panelWidth: CGFloat = 360
    private let maxContentHeight: CGFloat = 200

    // Drag state
    @State private var isDragging = false
    @State private var dragStartPosition: CGPoint = .zero

    // Hover state
    @State private var isHoveringSaveButton = false
    @State private var isHoveringCopyURL = false
    @State private var isHoveringOpenInTab = false

    // Save state
    @State private var isSavedToReadingList = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            // Content area
            contentArea
        }
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
        .position(clampedPosition)
        .onAppear {
            checkIfSaved()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        ZStack {
            // Background drag area
            Color(nsColor: .controlBackgroundColor)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onHover { hovering in
                    if hovering && !isDragging {
                        NSCursor.openHand.push()
                    } else if !hovering && !isDragging {
                        NSCursor.pop()
                    }
                }

            // Content overlay
            VStack(spacing: 0) {
                // Drag handle indicator at top
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor).opacity(0.5))
                    .frame(width: 36, height: 4)
                    .padding(.top, 6)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    // Close button (red traffic light)
                    TrafficLightCloseButton {
                        onClose()
                    }

                    Spacer()

                    // Title
                    if let title = state.pageTitle {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 180)
                            .allowsHitTesting(false)
                    } else if state.isLoading {
                        Text("Loading...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .allowsHitTesting(false)
                    }

                    Spacer()

                    // Save to reading list button
                    saveToReadingListButton

                    // Copy URL button
                    copyURLButton

                    // Open in tab button
                    openInTabButton
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .frame(height: titleBarHeight)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Domain
            if let url = state.linkURL {
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
            }

            // Summary or loading state
            if let summary = state.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(8)
            } else if let error = state.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .systemRed))
                    .lineLimit(2)
            } else if state.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("Generating summary...")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxContentHeight)
    }

    // MARK: - Action Buttons

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
            withAnimation(.easeInOut(duration: 0.1)) {
                isHoveringSaveButton = hovering
            }
        }
        .help(isSavedToReadingList ? "Remove from reading list" : "Save to reading list")
    }

    private var copyURLButton: some View {
        Button {
            if let url = state.linkURL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            onCopyURL()
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
            withAnimation(.easeInOut(duration: 0.1)) {
                isHoveringCopyURL = hovering
            }
        }
        .help("Copy URL")
    }

    private var openInTabButton: some View {
        Button {
            onOpenInTab()
        } label: {
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
            withAnimation(.easeInOut(duration: 0.1)) {
                isHoveringOpenInTab = hovering
            }
        }
        .help("Open in new tab")
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPosition = state.position
                    NSCursor.closedHand.push()
                }

                let newX = dragStartPosition.x + value.translation.width
                let newY = dragStartPosition.y + value.translation.height

                state.position = CGPoint(x: newX, y: newY)
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.pop()
            }
    }

    // MARK: - Position Clamping

    private var clampedPosition: CGPoint {
        let minVisiblePortion: CGFloat = 100
        let edgeMargin: CGFloat = 12

        var x = state.position.x
        var y = state.position.y

        // Clamp X to keep window visible
        let minX = panelWidth / 2 + edgeMargin
        let maxX = containerSize.width - panelWidth / 2 - edgeMargin
        x = max(minX, min(x, maxX))

        // Clamp Y to keep title bar visible at top
        let minY = titleBarHeight / 2 + edgeMargin
        let maxY = containerSize.height - minVisiblePortion
        y = max(minY, min(y, maxY))

        return CGPoint(x: x, y: y)
    }

    // MARK: - Reading List

    private func toggleSaveToReadingList() {
        guard let url = state.linkURL else { return }

        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let title = state.pageTitle ?? url.host ?? "Untitled"
                let newState = try await database.toggleSaved(url: url.absoluteString, title: title)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                Log.LinkPreview.error("Failed to toggle save state: \(error)")
            }
        }
    }

    private func checkIfSaved() {
        guard let url = state.linkURL else { return }

        Task {
            do {
                let database = SearchDatabase.shared
                try await database.initialize()
                let saved = try await database.isSaved(url: url.absoluteString)

                await MainActor.run {
                    isSavedToReadingList = saved
                }
            } catch {
                Log.LinkPreview.error("Failed to check saved state: \(error)")
            }
        }
    }
}

// MARK: - Traffic Light Close Button

private struct TrafficLightCloseButton: View {
    let action: () -> Void

    @State private var isHovered = false

    private let size: CGFloat = 12

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: size, height: size)

                if isHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(Color(nsColor: .textBackgroundColor).opacity(0.8))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}
