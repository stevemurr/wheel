import SwiftUI

/// Always-visible left-side tab strip inspired by macOS Stage Manager.
///
/// **Collapsed (default):** tiny binder-tab peeks along the left edge — color-coded
/// slivers that look like notebook divider tabs.
/// **Expanded (on hover):** full 3D-tilted thumbnail previews slide in.
struct StageManagerStrip: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var screenshotManager: TabScreenshotManager

    @State private var isExpanded = false

    /// Delay timer so the strip doesn't collapse the instant the cursor wanders off.
    @State private var collapseWork: DispatchWorkItem?

    /// Width of the invisible hover-detection zone (always present).
    private let hoverZoneWidth: CGFloat = 130
    private let collapseDelay: TimeInterval = 0.35

    var body: some View {
        // The hover zone is always full-width so the expanded thumbnails
        // remain interactive; the visible content animates inside it.
        ZStack(alignment: .leading) {
            // Invisible hover target — always the full zone width
            Color.clear
                .frame(width: hoverZoneWidth)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        // Cancel any pending collapse and expand immediately
                        collapseWork?.cancel()
                        collapseWork = nil
                        withAnimation(AppAnimation.panelSpring) {
                            isExpanded = true
                        }
                    } else {
                        // Delay collapse so brief cursor exits don't flicker
                        let work = DispatchWorkItem { [self] in
                            withAnimation(AppAnimation.panelSpring) {
                                isExpanded = false
                            }
                        }
                        collapseWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
                    }
                }

            if isExpanded {
                expandedContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                collapsedContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: hoverZoneWidth, alignment: .leading)
        .allowsHitTesting(true)
    }

    // MARK: - Expanded (full thumbnails)

    private var expandedContent: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(browserState.tabs) { tab in
                        StageManagerThumbnail(
                            tab: tab,
                            screenshotManager: screenshotManager,
                            isActive: tab.id == browserState.activeTabId,
                            canClose: browserState.tabs.count > 1,
                            onSelect: {
                                browserState.selectTab(tab.id)
                            },
                            onClose: {
                                withAnimation(AppAnimation.springSnappy) {
                                    browserState.closeTab(tab.id)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
            }

        }
        .frame(width: hoverZoneWidth)
    }

    // MARK: - Collapsed (binder-tab peeks)

    private var collapsedContent: some View {
        VStack(spacing: 4) {
            ForEach(browserState.tabs) { tab in
                BinderTabPeek(
                    tab: tab,
                    isActive: tab.id == browserState.activeTabId,
                    onSelect: {
                        browserState.selectTab(tab.id)
                    }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
    }
}

// MARK: - Binder Tab Peek

/// A tiny sliver that sticks out from the left window edge — like a physical
/// notebook divider tab. Color-coded by domain, with the active tab highlighted.
private struct BinderTabPeek: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private var peekWidth: CGFloat {
        isActive ? 14 : (isHovered ? 12 : 8)
    }

    private let peekHeight: CGFloat = 32

    var body: some View {
        // The tab shape: left edge is flush/straight, right edge is rounded
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: 0,
                bottomTrailing: 5,
                topTrailing: 5
            ),
            style: .continuous
        )
        .fill(tabColor)
        .frame(width: peekWidth, height: peekHeight)
        .overlay(alignment: .trailing) {
            // Accent stripe on the right edge for the active tab
            if isActive {
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: 0,
                        bottomTrailing: 5,
                        topTrailing: 5
                    ),
                    style: .continuous
                )
                .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 1.5)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, x: 1, y: 1)
        .animation(AppAnimation.hoverSpring, value: isHovered)
        .animation(AppAnimation.hoverSpring, value: isActive)
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .help(tab.displayTitle)
    }

    private var tabColor: Color {
        if tab.hasActiveAgent {
            return .green.opacity(0.8)
        }
        if tab.isChatTab {
            return .purple.opacity(0.7)
        }
        return DomainGradient.solidColor(for: tab.url?.host)
    }
}
