import SwiftUI
import AppKit

/// Always-visible left-side tab strip inspired by macOS Stage Manager.
///
/// **Collapsed (default):** tiny binder-tab peeks along the left edge.
/// **Expanded (on hover):** full 3D-tilted thumbnail previews slide in.
struct StageManagerStrip: View {
    var browserState: BrowserState
    var screenshotManager: TabScreenshotManager
    let onCreateFolder: ([UUID]) -> Void
    let onRenameFolder: (UUID) -> Void

    @AppStorage(AppSettings.hiddenTabScaleKey)
    private var hiddenTabScale = AppSettings.defaultHiddenTabScale

    @AppStorage(AppSettings.shownTabScaleKey)
    private var shownTabScale = AppSettings.defaultShownTabScale

    @State private var isExpanded = false
    @State private var collapseWork: DispatchWorkItem?

    private let collapseDelay: TimeInterval = 0.42
    private let minimumHotZoneHeight: CGFloat = 240
    private let hotZoneVerticalForgiveness: CGFloat = 80
    private let expandedHotZoneTrailingPadding: CGFloat = 28

    private var visibleTabs: [Tab] {
        browserState.visibleTabs
    }

    private var selectionTint: Color {
        browserState.activeFolder?.accentColor ?? Color(nsColor: .controlAccentColor)
    }

    private var revealHotZoneWidth: CGFloat {
        max(24, collapsedPeekMaxWidth + 14)
    }

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
            if visibleTabs.isEmpty {
                emptyFolderState
                    .frame(width: expandedDockWidth)
                    .frame(minHeight: containerHeight, alignment: .center)
            } else {
                ZStack(alignment: .topLeading) {
                    LazyVStack(spacing: expandedTabSpacing) {
                        ForEach(visibleTabs) { tab in
                            StageManagerThumbnail(
                                tab: tab,
                                screenshotManager: screenshotManager,
                                isActive: tab.id == browserState.activeTabId,
                                isSelected: browserState.isTabSelected(tab.id),
                                canClose: browserState.tabs.count > 1,
                                selectionTint: selectionTint,
                                sizeScale: shownScale,
                                onSelect: { modifiers in
                                    handleTabClick(tab.id, modifiers: modifiers)
                                },
                                onClose: {
                                    withAnimation(AppAnimation.springSnappy) {
                                        browserState.closeTab(tab.id)
                                    }
                                }
                            )
                            .contextMenu {
                                tabContextMenu(for: tab)
                            }
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: SelectedTabFramePreferenceKey.self,
                                        value: browserState.isTabSelected(tab.id)
                                            ? [tab.id: proxy.frame(in: .named("stage-manager-expanded"))]
                                            : [:]
                                    )
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "stage-manager-expanded")
                .overlayPreferenceValue(SelectedTabFramePreferenceKey.self) { frames in
                    selectionClusterOverlay(from: frames)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
                .frame(minHeight: containerHeight, alignment: .center)
            }
        }
        .frame(width: expandedDockWidth)
    }

    // MARK: - Collapsed (binder-tab peeks)

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: collapsedTabSpacing) {
                ForEach(visibleTabs) { tab in
                    BinderTabPeek(
                        tab: tab,
                        isActive: tab.id == browserState.activeTabId,
                        sizeScale: hiddenScale,
                        onSelect: { modifiers in
                            handleTabClick(tab.id, modifiers: modifiers)
                        }
                    )
                    .contextMenu {
                        tabContextMenu(for: tab)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: revealHotZoneWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private var emptyFolderState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Empty Folder")
                .font(.system(size: 12, weight: .semibold))

            Text("Create a tab or move one here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selectionTint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selectionTint.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func selectionClusterOverlay(from frames: [UUID: CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(selectionClusterRects(from: frames)) { cluster in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selectionTint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selectionTint.opacity(0.24), lineWidth: 1)
                    )
                    .frame(width: expandedDockWidth - 4, height: cluster.rect.height)
                    .offset(x: 2, y: cluster.rect.minY)
            }
        }
        .allowsHitTesting(false)
    }

    private func selectionClusterRects(from frames: [UUID: CGRect]) -> [SelectionClusterRect] {
        let selectedIndices = visibleTabs.enumerated().compactMap { index, tab -> Int? in
            browserState.isTabSelected(tab.id) ? index : nil
        }

        guard !selectedIndices.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var rangeStart = selectedIndices[0]
        var previous = selectedIndices[0]

        for index in selectedIndices.dropFirst() {
            if index == previous + 1 {
                previous = index
            } else {
                ranges.append(rangeStart...previous)
                rangeStart = index
                previous = index
            }
        }

        ranges.append(rangeStart...previous)

        return ranges.compactMap { range in
            let rangeTabs = visibleTabs[range].compactMap { frames[$0.id] }
            guard let minY = rangeTabs.map(\.minY).min(),
                  let maxY = rangeTabs.map(\.maxY).max() else {
                return nil
            }

            return SelectionClusterRect(rect: CGRect(
                x: 0,
                y: max(0, minY - 6),
                width: expandedDockWidth - 4,
                height: (maxY - minY) + 12
            ))
        }
    }

    private func handleTabClick(_ tabId: UUID, modifiers: NSEvent.ModifierFlags) {
        browserState.handleTabActivation(tabId, selectionMode: selectionMode(for: modifiers))
    }

    private func selectionMode(for modifiers: NSEvent.ModifierFlags) -> TabSelectionMode {
        if modifiers.contains(.shift) {
            return .range
        }
        if modifiers.contains(.command) {
            return .add
        }
        return .replace
    }

    @ViewBuilder
    private func tabContextMenu(for tab: Tab) -> some View {
        let targetTabIDs = browserState.contextActionTabIDs(for: tab.id)

        Button("New Folder from Selection") {
            onCreateFolder(targetTabIDs)
        }

        if !browserState.folders.isEmpty {
            Menu("Move to Folder…") {
                ForEach(browserState.folders) { folder in
                    Button(folder.name) {
                        browserState.moveTabs(targetTabIDs, toFolder: folder.id)
                    }
                }
            }
        }

        if tab.folderID != nil {
            Button("Remove from Folder") {
                browserState.removeTabsFromFolders(targetTabIDs)
            }
        }

        if let folderID = tab.folderID {
            Divider()

            Button("Rename Folder") {
                onRenameFolder(folderID)
            }

            Button("Delete Folder", role: .destructive) {
                browserState.deleteFolder(folderID)
            }
        }
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
        let count = CGFloat(visibleTabs.count)
        guard count > 0 else { return minimumHotZoneHeight }
        let gaps = max(0, count - 1)
        return count * itemHeight + gaps * spacing + verticalPadding
    }
}

// MARK: - Binder Tab Peek

private struct BinderTabPeek: View {
    var tab: Tab
    let isActive: Bool
    let sizeScale: CGFloat
    let onSelect: (NSEvent.ModifierFlags) -> Void

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
        .onTapGesture {
            onSelect(NSApp.currentEvent?.modifierFlags ?? [])
        }
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

private struct SelectedTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SelectionClusterRect: Identifiable {
    let id = UUID()
    let rect: CGRect
}

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}
