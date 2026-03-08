import SwiftUI

/// Always-visible left-side tab strip inspired by macOS Stage Manager.
///
/// **Collapsed (default):** tiny binder-tab peeks along the left edge — color-coded
/// slivers that look like notebook divider tabs.
/// **Expanded (on hover):** full 3D-tilted thumbnail previews slide in.
struct StageManagerStrip: View {
    var browserState: BrowserState
    var screenshotManager: TabScreenshotManager

    @AppStorage(AppSettings.hiddenTabScaleKey)
    private var hiddenTabScale = AppSettings.defaultHiddenTabScale

    @AppStorage(AppSettings.shownTabScaleKey)
    private var shownTabScale = AppSettings.defaultShownTabScale

    @State private var isExpanded = false

    /// Delay timer so the strip doesn't collapse the instant the cursor wanders off.
    @State private var collapseWork: DispatchWorkItem?

    private let collapseDelay: TimeInterval = 0.42
    private let minimumHotZoneHeight: CGFloat = 240
    private let hotZoneVerticalForgiveness: CGFloat = 80
    private let expandedHotZoneTrailingPadding: CGFloat = 28

    /// Narrow reveal strip when collapsed so the dock doesn't pop open from anywhere near the edge.
    private var revealHotZoneWidth: CGFloat {
        max(24, collapsedPeekMaxWidth + 14)
    }

    /// Wider interaction zone when expanded so the dock stays open while the pointer
    /// moves around the visible thumbnails or just past their right edge.
    private var expandedHotZoneWidth: CGFloat {
        expandedDockWidth + expandedHotZoneTrailingPadding
    }

    private var activeHotZoneWidth: CGFloat {
        isExpanded ? expandedHotZoneWidth : revealHotZoneWidth
    }

    private var expandedDockWidth: CGFloat {
        StageManagerThumbnail.baseThumbnailWidth * shownScale + 12
    }

    private var shownScale: CGFloat {
        CGFloat(clamp(shownTabScale, to: AppSettings.shownTabScaleRange))
    }

    private var hiddenScale: CGFloat {
        CGFloat(clamp(hiddenTabScale, to: AppSettings.hiddenTabScaleRange))
    }

    private var expandedTabSpacing: CGFloat {
        10 * max(0.9, shownScale)
    }

    private var collapsedTabSpacing: CGFloat {
        4 * max(0.85, hiddenScale)
    }

    private var shownThumbnailHeight: CGFloat {
        StageManagerThumbnail.baseThumbnailHeight * shownScale
    }

    private var collapsedPeekMaxWidth: CGFloat {
        14 * hiddenScale
    }

    private var collapsedPeekHeight: CGFloat {
        32 * hiddenScale
    }

    private var expandedStackHeight: CGFloat {
        stackHeight(itemHeight: shownThumbnailHeight, spacing: expandedTabSpacing, verticalPadding: 24)
    }

    private var collapsedStackHeight: CGFloat {
        stackHeight(itemHeight: collapsedPeekHeight, spacing: collapsedTabSpacing, verticalPadding: 0)
    }

    var body: some View {
        GeometryReader { geometry in
            // The hot zone stays centered around the actual tab stack instead of spanning
            // the entire window height, which reduces accidental reveals near the corners.
            ZStack(alignment: .leading) {
                Color.clear
                    .frame(
                        width: activeHotZoneWidth,
                        height: activeHotZoneHeight(in: geometry.size.height)
                    )
                    .contentShape(Rectangle())
                    .frame(maxHeight: .infinity, alignment: .center)
                    .onHover(perform: handleHotZoneHover)

                if isExpanded {
                    expandedContent(containerHeight: geometry.size.height)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    collapsedContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: activeHotZoneWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(true)
        }
        .frame(width: activeHotZoneWidth)
    }

    // MARK: - Expanded (full thumbnails)

    private func expandedContent(containerHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: expandedTabSpacing) {
                ForEach(browserState.tabs) { tab in
                    StageManagerThumbnail(
                        tab: tab,
                        screenshotManager: screenshotManager,
                        isActive: tab.id == browserState.activeTabId,
                        canClose: browserState.tabs.count > 1,
                        sizeScale: shownScale,
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(minHeight: containerHeight, alignment: .center)
        }
        .frame(width: expandedDockWidth)
    }

    // MARK: - Collapsed (binder-tab peeks)

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: collapsedTabSpacing) {
                ForEach(browserState.tabs) { tab in
                    BinderTabPeek(
                        tab: tab,
                        isActive: tab.id == browserState.activeTabId,
                        sizeScale: hiddenScale,
                        onSelect: {
                            browserState.selectTab(tab.id)
                        }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: revealHotZoneWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private func handleHotZoneHover(_ hovering: Bool) {
        if hovering {
            collapseWork?.cancel()
            collapseWork = nil
            withAnimation(AppAnimation.panelSpring) {
                isExpanded = true
            }
        } else {
            let work = DispatchWorkItem { [self] in
                withAnimation(AppAnimation.panelSpring) {
                    isExpanded = false
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }

    private func activeHotZoneHeight(in containerHeight: CGFloat) -> CGFloat {
        let naturalHeight = isExpanded ? expandedStackHeight : collapsedStackHeight
        let targetHeight = max(minimumHotZoneHeight, naturalHeight + hotZoneVerticalForgiveness)
        return min(containerHeight, targetHeight)
    }

    private func stackHeight(itemHeight: CGFloat, spacing: CGFloat, verticalPadding: CGFloat) -> CGFloat {
        let count = CGFloat(browserState.tabs.count)
        guard count > 0 else { return minimumHotZoneHeight }
        let gaps = max(0, count - 1)
        return count * itemHeight + gaps * spacing + verticalPadding
    }
}

// MARK: - Binder Tab Peek

/// A tiny sliver that sticks out from the left window edge — like a physical
/// notebook divider tab. Color-coded by domain, with the active tab highlighted.
private struct BinderTabPeek: View {
    var tab: Tab
    let isActive: Bool
    let sizeScale: CGFloat
    let onSelect: () -> Void

    @State private var isHovered = false

    private var peekWidth: CGFloat {
        let baseWidth: CGFloat
        if tab.hasActiveAgent {
            baseWidth = isHovered ? 16.0 : 13.0
        } else {
            baseWidth = isActive ? 14.0 : (isHovered ? 12.0 : 8.0)
        }
        return baseWidth * sizeScale
    }

    private var peekHeight: CGFloat {
        32 * sizeScale
    }

    private var peekCornerRadius: CGFloat {
        5 * sizeScale
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let glowPhase = glowPulse(for: context.date)

            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: 0,
                    bottomTrailing: peekCornerRadius,
                    topTrailing: peekCornerRadius
                ),
                style: .continuous
            )
            .fill(tabColor)
            .frame(width: peekWidth, height: peekHeight)
            .overlay {
                if tab.hasActiveAgent {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 0,
                            bottomLeading: 0,
                            bottomTrailing: peekCornerRadius,
                            topTrailing: peekCornerRadius
                        ),
                        style: .continuous
                    )
                    .stroke(Color.green.opacity(0.2 + (0.12 * glowPhase)), lineWidth: max(2, 3 * sizeScale))
                    .blur(radius: 4 + (3 * glowPhase))
                }
            }
            .overlay(alignment: .trailing) {
                if tab.hasActiveAgent {
                    AgentAutomationOrb(size: max(4, 5 * sizeScale))
                        .offset(x: 4 * sizeScale)
                }

                if tab.hasActiveAgent || isActive {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 0,
                            bottomLeading: 0,
                            bottomTrailing: peekCornerRadius,
                            topTrailing: peekCornerRadius
                        ),
                        style: .continuous
                    )
                    .strokeBorder(
                        tab.hasActiveAgent ? Color.green.opacity(0.82 + (0.12 * glowPhase)) : Color(nsColor: .controlAccentColor),
                        lineWidth: max(1, 1.5 * sizeScale)
                    )
                }
            }
            .shadow(
                color: tab.hasActiveAgent
                    ? Color.green.opacity(0.28 + (0.16 * glowPhase))
                    : .black.opacity(0.25),
                radius: tab.hasActiveAgent ? (8 * sizeScale) + (3 * sizeScale * glowPhase) : 2 * sizeScale,
                x: sizeScale,
                y: sizeScale
            )
        }
        .animation(AppAnimation.hoverSpring, value: isHovered)
        .animation(AppAnimation.hoverSpring, value: isActive)
        .animation(AppAnimation.hoverSpring, value: tab.hasActiveAgent)
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .help(tab.hasActiveAgent ? "\(tab.displayTitle) (Agent running)" : tab.displayTitle)
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

    private func glowPulse(for date: Date) -> Double {
        let cycle = 1.2
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return (sin((time / cycle) * (.pi * 2)) + 1) / 2
    }
}

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}
