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

    // Constants
    private let cornerRadius: CGFloat = 12
    private let titleBarHeight: CGFloat = 36
    private let minSize = CGSize(width: 300, height: 200)
    private let minVisiblePortion: CGFloat = 100
    private let resizeHandleSize: CGFloat = 8

    // Drag state
    @State private var isDragging = false
    @State private var dragStartPosition: CGPoint = .zero

    // Resize state
    @State private var isResizing = false
    @State private var resizeEdge: ResizeEdge? = nil
    @State private var initialSize: CGSize = .zero
    @State private var initialPosition: CGPoint = .zero

    // Hover state
    @State private var isHoveringOpenInTab = false
    @State private var isHoveringReaderMode = false
    @State private var isHoveringSaveButton = false
    @State private var isHoveringCopyURL = false

    // Loading state
    @State private var isLoading = true

    // Reader mode state
    @State private var isReaderMode = false

    // Save to reading list state
    @State private var isSavedToReadingList = false

    var body: some View {
        ZStack {
            // Main window content
            VStack(spacing: 0) {
                // Title bar
                titleBar

                // WebView content area
                ZStack {
                    OverlayWebView(url: item.url, item: item, isLoading: $isLoading, isReaderMode: $isReaderMode)

                    // Loading indicator
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: item.size.width, height: item.size.height)
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

            // Resize handles (only when not maximized)
            if !item.isMaximized {
                resizeHandles
            }
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    onBringToFront()
                }
        )
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        ZStack {
            // Background drag area - covers entire title bar
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
                    // Traffic light buttons (these need to be clickable)
                    trafficLightButtons

                    Spacer()

                    // Title (draggable area)
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200)
                        .allowsHitTesting(false)

                    Spacer()

                    // Reader mode button
                    readerModeButton

                    // Save to reading list button
                    saveToReadingListButton

                    // Copy URL button
                    copyURLButton

                    // Open in tab button (needs to be clickable)
                    openInTabButton
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .frame(height: titleBarHeight)
    }

    // MARK: - Traffic Light Buttons

    private var trafficLightButtons: some View {
        HStack(spacing: 6) {
            // Close button (red)
            TrafficLightButton(color: .red, icon: "xmark") {
                onClose()
            }

            // Minimize button (yellow)
            TrafficLightButton(color: .yellow, icon: "minus") {
                onMinimize()
            }

            // Maximize button (green)
            TrafficLightButton(color: .green, icon: item.isMaximized ? "arrow.down.right.and.arrow.up.left" : "plus") {
                onToggleMaximize()
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

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPosition = item.position
                    onBringToFront()
                    NSCursor.closedHand.push()
                }

                let newX = dragStartPosition.x + value.translation.width
                let newY = dragStartPosition.y + value.translation.height

                // Clamp position to keep at least minVisiblePortion visible
                let clampedX = clampX(newX)
                let clampedY = clampY(newY)

                onUpdatePosition(CGPoint(x: clampedX, y: clampedY))
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.pop()
            }
    }

    // MARK: - Position Clamping

    private func clampX(_ x: CGFloat) -> CGFloat {
        let minX = -item.size.width + minVisiblePortion
        let maxX = containerSize.width - minVisiblePortion
        return max(minX, min(x, maxX))
    }

    private func clampY(_ y: CGFloat) -> CGFloat {
        let minY: CGFloat = 0 // Keep title bar always visible at top
        let maxY = containerSize.height - minVisiblePortion
        return max(minY, min(y, maxY))
    }

    // MARK: - Resize Handles

    private var resizeHandles: some View {
        ZStack {
            // Corner handles
            ResizeHandle(edge: .topLeft)
                .position(x: 0, y: 0)
                .gesture(resizeGesture(edge: .topLeft))

            ResizeHandle(edge: .topRight)
                .position(x: item.size.width, y: 0)
                .gesture(resizeGesture(edge: .topRight))

            ResizeHandle(edge: .bottomLeft)
                .position(x: 0, y: item.size.height)
                .gesture(resizeGesture(edge: .bottomLeft))

            ResizeHandle(edge: .bottomRight)
                .position(x: item.size.width, y: item.size.height)
                .gesture(resizeGesture(edge: .bottomRight))

            // Edge handles
            ResizeHandle(edge: .top)
                .position(x: item.size.width / 2, y: 0)
                .gesture(resizeGesture(edge: .top))

            ResizeHandle(edge: .bottom)
                .position(x: item.size.width / 2, y: item.size.height)
                .gesture(resizeGesture(edge: .bottom))

            ResizeHandle(edge: .left)
                .position(x: 0, y: item.size.height / 2)
                .gesture(resizeGesture(edge: .left))

            ResizeHandle(edge: .right)
                .position(x: item.size.width, y: item.size.height / 2)
                .gesture(resizeGesture(edge: .right))
        }
        .frame(width: item.size.width, height: item.size.height)
    }

    // MARK: - Resize Gesture

    private func resizeGesture(edge: ResizeEdge) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    resizeEdge = edge
                    initialSize = item.size
                    initialPosition = item.position
                    onBringToFront()
                }

                let delta = value.translation
                var newSize = initialSize
                var newPosition = initialPosition

                // Handle horizontal resizing
                switch edge {
                case .left, .topLeft, .bottomLeft:
                    let widthDelta = -delta.width
                    let newWidth = max(minSize.width, initialSize.width + widthDelta)
                    let actualWidthChange = newWidth - initialSize.width
                    newSize.width = newWidth
                    newPosition.x = initialPosition.x - actualWidthChange

                case .right, .topRight, .bottomRight:
                    newSize.width = max(minSize.width, initialSize.width + delta.width)

                default:
                    break
                }

                // Handle vertical resizing
                switch edge {
                case .top, .topLeft, .topRight:
                    let heightDelta = -delta.height
                    let newHeight = max(minSize.height, initialSize.height + heightDelta)
                    let actualHeightChange = newHeight - initialSize.height
                    newSize.height = newHeight
                    newPosition.y = initialPosition.y - actualHeightChange

                case .bottom, .bottomLeft, .bottomRight:
                    newSize.height = max(minSize.height, initialSize.height + delta.height)

                default:
                    break
                }

                // Clamp position after resize
                newPosition.x = clampX(newPosition.x)
                newPosition.y = clampY(newPosition.y)

                // Update via callbacks
                onUpdateSize(newSize)
                onUpdatePosition(newPosition)
            }
            .onEnded { _ in
                isResizing = false
                resizeEdge = nil
            }
    }
}

// MARK: - Resize Edge

private enum ResizeEdge {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        case .topLeft, .bottomRight:
            return .crosshair // macOS doesn't have diagonal cursors by default
        case .topRight, .bottomLeft:
            return .crosshair
        }
    }
}

// MARK: - Resize Handle View

private struct ResizeHandle: View {
    let edge: ResizeEdge

    private let handleSize: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    edge.cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var frameSize: CGSize {
        switch edge {
        case .top, .bottom:
            return CGSize(width: 40, height: handleSize)
        case .left, .right:
            return CGSize(width: handleSize, height: 40)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return CGSize(width: handleSize, height: handleSize)
        }
    }
}

// MARK: - Traffic Light Button

private struct TrafficLightButton: View {
    let color: Color
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    private let size: CGFloat = 12

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)

                if isHovered {
                    Image(systemName: icon)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(Color(nsColor: .textBackgroundColor).opacity(0.8))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}
