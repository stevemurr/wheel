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
    private let contextMenuState = ContextMenuState.shared

    @AppStorage(AppSettings.hiddenTabScaleKey)
    private var hiddenTabScale = AppSettings.defaultHiddenTabScale

    @AppStorage(AppSettings.shownTabScaleKey)
    private var shownTabScale = AppSettings.defaultShownTabScale

    @State private var isExpanded = false
    @State private var collapseWork: DispatchWorkItem?
    @State private var isHotZoneHovered = false

    private let collapseDelay: TimeInterval = 0.42
    private let minimumHotZoneHeight: CGFloat = 240
    private let hotZoneVerticalForgiveness: CGFloat = 80
    private let expandedHotZoneTrailingPadding: CGFloat = 28

    private var visibleTabs: [Tab] {
        browserState.visibleTabs
    }

    private var selectionTint: Color {
        if let activeTab = browserState.activeTab,
           let folder = browserState.folder(for: activeTab.folderID) {
            return folder.accentColor
        }
        return browserState.activeFolder?.accentColor ?? Color(nsColor: .controlAccentColor)
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
                    .onHover { hovering in
                        isHotZoneHovered = hovering
                        handleHotZoneHover(hovering)
                    }

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
        .onChange(of: contextMenuState.isVisible) { _, isVisible in
            if isVisible {
                collapseWork?.cancel()
                collapseWork = nil
            } else if !isHotZoneHovered {
                scheduleCollapse()
            }
        }
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
                                groupColor: groupColor(for: tab),
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
                            .overlay(
                                RightClickContextMenuTrigger { point in
                                    presentTabContextMenu(for: tab, at: point)
                                }
                            )
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
                        groupColor: groupColor(for: tab),
                        onSelect: { modifiers in
                            handleTabClick(tab.id, modifiers: modifiers)
                        }
                    )
                    .overlay(
                        RightClickContextMenuTrigger { point in
                            presentTabContextMenu(for: tab, at: point)
                        }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: revealHotZoneWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private var emptyFolderState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No Tabs")
                .font(.system(size: 12, weight: .semibold))

            Text("Create a tab to get started.")
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

        guard selectedIndices.count > 1 else { return [] }

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

    private func groupColor(for tab: Tab) -> Color? {
        guard let folderID = tab.folderID,
              let folder = browserState.folder(for: folderID) else {
            return nil
        }

        return folder.accentColor
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

    private func presentTabContextMenu(for tab: Tab, at point: CGPoint) {
        contextMenuState.show(
            at: point,
            sections: tabContextMenuSections(for: tab),
            onAction: handleTabContextMenuAction
        )
    }

    private func tabContextMenuSections(for tab: Tab) -> [ContextMenuSection] {
        let targetTabIDs = browserState.contextActionTabIDs(for: tab.id)
        var sections: [ContextMenuSection] = [
            ContextMenuSection(items: [
                ContextMenuItem(
                    title: "New Folder from Selection",
                    systemImage: "folder.badge.plus",
                    action: .createFolderFromTabs(targetTabIDs)
                )
            ])
        ]

        if !browserState.folders.isEmpty {
            sections.append(
                ContextMenuSection(
                    items: browserState.folders.map { folder in
                        ContextMenuItem(
                            title: "Move to \(folder.name)",
                            systemImage: "folder",
                            action: .moveTabsToFolder(tabIDs: targetTabIDs, folderID: folder.id)
                        )
                    }
                )
            )
        }

        if tab.folderID != nil {
            sections.append(
                ContextMenuSection(items: [
                    ContextMenuItem(
                        title: "Remove from Folder",
                        systemImage: "folder.badge.minus",
                        action: .removeTabsFromFolders(targetTabIDs)
                    )
                ])
            )
        }

        if let folderID = tab.folderID {
            sections.append(
                ContextMenuSection(items: [
                    ContextMenuItem(
                        title: "Rename Folder",
                        systemImage: "pencil",
                        action: .renameFolder(folderID)
                    ),
                    ContextMenuItem(
                        title: "Delete Folder",
                        systemImage: "trash",
                        action: .deleteFolder(folderID)
                    )
                ])
            )
        }

        return sections
    }

    private func handleTabContextMenuAction(_ action: ContextMenuAction) {
        switch action {
        case .createFolderFromTabs(let tabIDs):
            onCreateFolder(tabIDs)
        case .moveTabsToFolder(let tabIDs, let folderID):
            browserState.moveTabs(tabIDs, toFolder: folderID)
        case .removeTabsFromFolders(let tabIDs):
            browserState.removeTabsFromFolders(tabIDs)
        case .renameFolder(let folderID):
            onRenameFolder(folderID)
        case .deleteFolder(let folderID):
            browserState.deleteFolder(folderID)
        default:
            break
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
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        guard !contextMenuState.isVisible else { return }
        let work = DispatchWorkItem { [self] in
            guard !contextMenuState.isVisible else { return }
            withAnimation(AppAnimation.panelSpring) {
                isExpanded = false
            }
        }
        collapseWork?.cancel()
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
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
    let groupColor: Color?
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

    private var groupAccentColor: Color? { groupColor }

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

                if tab.hasActiveAgent || isActive || groupAccentColor != nil {
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
                        tab.hasActiveAgent
                            ? Color.green.opacity(0.82 + (0.12 * glowPhase))
                            : (groupAccentColor?.opacity(isActive ? 0.88 : 0.5) ?? Color(nsColor: .controlAccentColor)),
                        lineWidth: max(1, 1.5 * sizeScale)
                    )
                }
            }
            .shadow(
                color: tab.hasActiveAgent
                    ? Color.green.opacity(0.28 + (0.16 * glowPhase))
                    : (groupAccentColor?.opacity(isActive ? 0.22 : 0.12) ?? .black.opacity(0.25)),
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
        if let groupAccentColor {
            return groupAccentColor.opacity(isActive ? 0.88 : (isHovered ? 0.78 : 0.68))
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

private struct RightClickContextMenuTrigger: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> TabContextMenuTriggerView {
        let view = TabContextMenuTriggerView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: TabContextMenuTriggerView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

private final class TabContextMenuTriggerView: NSView {
    var onRightClick: ((CGPoint) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    private func updateMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        guard window != nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window == window else {
                return event
            }

            let localPoint = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPoint) else {
                return event
            }

            let windowPoint = self.convert(localPoint, to: nil)
            let content = window.contentLayoutRect
            let swiftUIPoint = CGPoint(
                x: windowPoint.x - content.origin.x,
                y: content.height - (windowPoint.y - content.origin.y)
            )

            DispatchQueue.main.async {
                self.onRightClick?(swiftUIPoint)
            }
            return nil
        }
    }

    override func removeFromSuperview() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.removeFromSuperview()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}
