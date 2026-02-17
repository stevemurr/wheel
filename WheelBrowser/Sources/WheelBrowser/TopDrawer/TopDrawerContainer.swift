import SwiftUI

// MARK: - Top Drawer Container

struct TopDrawerContainer: View {
    @State private var isHovered = false
    @State private var isVisible = false
    @State private var isSheetPresented = false
    @State private var pendingHideWorkItem: DispatchWorkItem?

    private let drawerHeight: CGFloat = 300
    private let cornerRadius: CGFloat = 16
    private let revealZoneHeight: CGFloat = 20
    private let safeZoneHeight: CGFloat = 50
    private let hideDelay: TimeInterval = 0.4  // Slightly longer delay for easier use

    var body: some View {
        ZStack(alignment: .top) {
            // Hover trigger zone - uses NSView tracking area, doesn't block clicks
            if !isVisible {
                HoverTrackingView { hovering in
                    if hovering {
                        cancelPendingHide()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            isVisible = true
                            isHovered = true
                        }
                    }
                }
                .frame(height: revealZoneHeight)
                .frame(maxWidth: .infinity)
            }

            // Subtle top-center hover zone indicator (pill shape)
            if !isVisible {
                hoverIndicator
            }

            // The drawer itself
            if isVisible {
                drawerContent
                    .onHover { hovering in
                        isHovered = hovering
                        if hovering {
                            cancelPendingHide()
                        } else if !isSheetPresented {
                            scheduleHide()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            // Don't dismiss when app loses focus if a sheet is open
            if !isSheetPresented {
                dismissDrawer()
            }
        }
        .background(
            // Escape key handler
            EscapeKeyHandler {
                dismissDrawer()
            }
        )
    }

    // MARK: - Hide Scheduling

    private func cancelPendingHide() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
    }

    private func scheduleHide() {
        cancelPendingHide()
        let workItem = DispatchWorkItem { [self] in
            if !isHovered && !isSheetPresented {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isVisible = false
                }
            }
        }
        pendingHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: workItem)
    }

    private func dismissDrawer() {
        cancelPendingHide()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            isVisible = false
        }
    }

    // MARK: - Hover Indicator

    private var hoverIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.4),
                        Color.gray.opacity(0.2)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 60, height: 5)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    // MARK: - Drawer Content

    private var drawerContent: some View {
        VStack(spacing: 0) {
            // Drawer header with close button and drag indicator
            ZStack {
                // Center: Drag indicator pill
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 40, height: 4)

                // Right: Close button
                HStack {
                    Spacer()
                    Button(action: dismissDrawer) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close drawer (Esc)")
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)

            // Main content area
            HStack(spacing: 0) {
                // Left: Workspaces
                WorkspacesView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .padding(.vertical, 8)

                // Right: Agent Studio
                AgentStudioView(
                    manager: AgentStudioManager.shared,
                    isSheetPresented: $isSheetPresented
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: drawerHeight)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color(nsColor: .windowBackgroundColor))
            .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 5)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Hover Tracking View

/// A view that tracks mouse hover without blocking clicks - passes all events through
struct HoverTrackingView: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverPassthroughView {
        let view = HoverPassthroughView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverPassthroughView, context: Context) {
        nsView.onHover = onHover
    }

    class HoverPassthroughView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        // Pass through all mouse events - don't intercept clicks
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}

// MARK: - Escape Key Handler

/// A view that captures the Escape key press and triggers the provided action
struct EscapeKeyHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyPressView()
        view.onEscape = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let keyView = nsView as? KeyPressView {
            keyView.onEscape = action
        }
    }

    class KeyPressView: NSView {
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape key
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.blue.opacity(0.3)
        TopDrawerContainer()
    }
    .frame(width: 800, height: 600)
}
