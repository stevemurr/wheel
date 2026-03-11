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
    private let contextMenuState = ContextMenuState.shared
    private static let coordinateSpaceName = "stage-manager-strip"

    @AppStorage(AppSettings.hiddenTabScaleKey)
    private var hiddenTabScale = AppSettings.defaultHiddenTabScale

    @AppStorage(AppSettings.shownTabScaleKey)
    private var shownTabScale = AppSettings.defaultShownTabScale

    @State private var isExpanded = false
    @State private var collapseWork: DispatchWorkItem?
    @State private var isHotZoneHovered = false
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var railFrames: [TabStripRailDropTarget: CGRect] = [:]
    @State private var dragSession: TabStripDragSession?

    private let collapseDelay: TimeInterval = 0.42
    private let minimumHotZoneHeight: CGFloat = 240
    private let hotZoneVerticalForgiveness: CGFloat = 80
    private let expandedHotZoneTrailingPadding: CGFloat = 28
    private let dragRailSpacing: CGFloat = 12
    private let dragRailWidth: CGFloat = 132

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

    private var stripWidth: CGFloat {
        isExpanded ? expandedDockWidth : revealHotZoneWidth
    }

    private var hoverRegionWidth: CGFloat {
        guard dragSession == nil else { return stripWidth }
        return (isExpanded || isHotZoneHovered) ? expandedHotZoneWidth : revealHotZoneWidth
    }

    private var contentWidth: CGFloat {
        stripWidth + (dragSession == nil ? 0 : (dragRailSpacing + dragRailWidth))
    }

    private var layoutWidth: CGFloat {
        max(contentWidth, hoverRegionWidth)
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

    private var dragRailTargets: [TabStripRailDropTarget] {
        [.loose] + browserState.folders.map { .folder($0.id) } + [.newGroup]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                StageManagerHoverRegion {
                    isHotZoneHovered = $0
                    handleHotZoneHover($0)
                }
                .frame(width: hoverRegionWidth, height: activeHotZoneHeight(in: geometry.size.height))
                .frame(maxHeight: .infinity, alignment: .center)

                HStack(alignment: .center, spacing: dragSession == nil ? 0 : dragRailSpacing) {
                    Group {
                        if isExpanded {
                            expandedContent(containerHeight: geometry.size.height)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        } else {
                            collapsedContent
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .frame(width: stripWidth, alignment: .leading)

                    if dragSession != nil {
                        dragGroupRail(containerHeight: geometry.size.height)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .frame(width: layoutWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(true)
        }
        .frame(width: layoutWidth)
        .onPreferenceChange(TabFramePreferenceKey.self) { frames in
            tabFrames = frames
        }
        .onPreferenceChange(TabStripRailFramePreferenceKey.self) { frames in
            railFrames = frames
        }
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
                            tabStripItem(for: tab, includesSelectionFrame: true) {
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
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
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
                    tabStripItem(for: tab) {
                        BinderTabPeek(
                            tab: tab,
                            isActive: tab.id == browserState.activeTabId,
                            sizeScale: hiddenScale,
                            groupColor: groupColor(for: tab),
                            onSelect: { modifiers in
                                handleTabClick(tab.id, modifiers: modifiers)
                            }
                        )
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
        guard dragSession == nil else { return }
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
            sections: tabContextMenuSections(for: tab)
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

    private func handleHotZoneHover(_ hovering: Bool) {
        guard dragSession == nil else { return }
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
        guard !contextMenuState.isVisible, dragSession == nil else { return }
        let work = DispatchWorkItem { [self] in
            guard !contextMenuState.isVisible, dragSession == nil else { return }
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

    @ViewBuilder
    private func tabStripItem<Content: View>(
        for tab: Tab,
        includesSelectionFrame: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(draggedOpacity(for: tab))
            .scaleEffect(draggedScale(for: tab))
            .offset(draggedOffset(for: tab))
            .zIndex(zIndex(for: tab))
            .overlay(alignment: .topTrailing) {
                if let badgeCount = dragBadgeCount(for: tab) {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectionTint)
                        )
                        .offset(x: 8, y: -8)
                }
            }
            .overlay {
                RightClickContextMenuTrigger { point in
                    presentTabContextMenu(for: tab, at: point)
                }
            }
            .overlay {
                dropDecoration(for: tab)
            }
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(Self.coordinateSpaceName))
                    Color.clear
                        .preference(key: TabFramePreferenceKey.self, value: [tab.id: frame])
                        .preference(
                            key: SelectedTabFramePreferenceKey.self,
                            value: includesSelectionFrame && browserState.isTabSelected(tab.id)
                                ? [tab.id: frame]
                                : [:]
                        )
                }
            )
            .simultaneousGesture(tabDragGesture(for: tab))
    }

    private func dragGroupRail(containerHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Move To")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                ForEach(dragRailTargets, id: \.self) { target in
                    dragRailTargetView(target)
                }
            }
            .padding(12)
            .frame(width: dragRailWidth, alignment: .leading)
            .frame(minHeight: containerHeight, alignment: .center)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private func dragRailTargetView(_ target: TabStripRailDropTarget) -> some View {
        let isHighlighted = dragSession?.hoverTarget?.matches(railTarget: target) == true
        let accentColor = railTargetColor(for: target)

        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(railTargetTitle(for: target))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(railTargetSubtitle(for: target))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? accentColor.opacity(0.18) : Color.white.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? accentColor.opacity(0.75) : Color.black.opacity(0.08), lineWidth: isHighlighted ? 1.4 : 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TabStripRailFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named(Self.coordinateSpaceName))]
                )
            }
        )
        .animation(AppAnimation.hoverSpring, value: isHighlighted)
    }

    private func tabDragGesture(for tab: Tab) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                handleDragChanged(for: tab, value: value)
            }
            .onEnded { value in
                handleDragEnded(for: tab, value: value)
            }
    }

    private func handleDragChanged(for tab: Tab, value: DragGesture.Value) {
        if dragSession == nil {
            beginDrag(for: tab, at: value.startLocation)
        }

        guard var session = dragSession else { return }
        session.translation = value.translation
        session.currentLocation = value.location
        session.hoverTarget = resolveHoverTarget(
            at: value.location,
            draggedTabIDs: session.draggedTabIDs,
            sourceFolderID: session.sourceFolderID
        )
        dragSession = session
    }

    private func handleDragEnded(for tab: Tab, value: DragGesture.Value) {
        guard let session = dragSession, session.leadTabID == tab.id else {
            dragSession = nil
            return
        }

        let dropTarget = resolveHoverTarget(
            at: value.location,
            draggedTabIDs: session.draggedTabIDs,
            sourceFolderID: session.sourceFolderID
        ) ?? session.hoverTarget

        applyDropTarget(dropTarget, draggedTabIDs: session.draggedTabIDs)

        withAnimation(AppAnimation.quickOut) {
            dragSession = nil
        }
    }

    private func beginDrag(for tab: Tab, at startLocation: CGPoint) {
        collapseWork?.cancel()
        contextMenuState.dismiss()

        let draggedTabIDs: [UUID]
        if browserState.isTabSelected(tab.id) {
            draggedTabIDs = browserState.contextActionTabIDs(for: tab.id)
        } else {
            browserState.selectTab(tab.id)
            draggedTabIDs = [tab.id]
        }

        withAnimation(AppAnimation.quick) {
            dragSession = TabStripDragSession(
                leadTabID: tab.id,
                draggedTabIDs: draggedTabIDs,
                sourceFolderID: tab.folderID,
                startLocation: startLocation,
                currentLocation: startLocation
            )
        }
    }

    private func resolveHoverTarget(
        at location: CGPoint,
        draggedTabIDs: [UUID],
        sourceFolderID: UUID?
    ) -> TabStripHoverTarget? {
        if let railTarget = resolvedRailTarget(at: location) {
            switch railTarget {
            case .loose:
                return .appendToFolder(nil)
            case .folder(let folderID):
                return .appendToFolder(folderID)
            case .newGroup:
                return .createNewFolder
            }
        }

        let draggedIDSet = Set(draggedTabIDs)
        if let hoveredTab = hoveredTab(at: location, excluding: draggedIDSet),
           let targetFolderID = hoveredTab.folderID,
           targetFolderID != sourceFolderID {
            return .moveToFolder(folderID: targetFolderID, placement: .after(hoveredTab.id))
        }

        return reorderPlacement(at: location, excluding: draggedIDSet).map(TabStripHoverTarget.reorder)
    }

    private func resolvedRailTarget(at location: CGPoint) -> TabStripRailDropTarget? {
        for target in dragRailTargets {
            guard let frame = railFrames[target] else { continue }
            if frame.contains(location) {
                return target
            }
        }
        return nil
    }

    private func hoveredTab(at location: CGPoint, excluding draggedIDSet: Set<UUID>) -> Tab? {
        for tab in visibleTabs where !draggedIDSet.contains(tab.id) {
            guard let frame = tabFrames[tab.id] else { continue }
            let hitFrame = frame.insetBy(dx: -28, dy: -4)
            if hitFrame.contains(location) {
                return tab
            }
        }
        return nil
    }

    private func reorderPlacement(at location: CGPoint, excluding draggedIDSet: Set<UUID>) -> TabInsertionPlacement? {
        let candidates = dropCandidates(excluding: draggedIDSet)
        guard !candidates.isEmpty else { return nil }

        if location.y < candidates[0].frame.midY {
            return .before(candidates[0].tab.id)
        }

        for index in candidates.indices.dropLast() {
            let current = candidates[index]
            let next = candidates[index + 1]
            if location.y < next.frame.midY {
                if location.y < current.frame.maxY {
                    return location.y < current.frame.midY ? .before(current.tab.id) : .after(current.tab.id)
                }
                return .after(current.tab.id)
            }
        }

        if let last = candidates.last {
            return location.y < last.frame.midY ? .before(last.tab.id) : .end
        }

        return .end
    }

    private func dropCandidates(excluding draggedIDSet: Set<UUID>) -> [(tab: Tab, frame: CGRect)] {
        visibleTabs.compactMap { tab in
            guard !draggedIDSet.contains(tab.id), let frame = tabFrames[tab.id] else {
                return nil
            }
            return (tab, frame)
        }
    }

    private func applyDropTarget(_ target: TabStripHoverTarget?, draggedTabIDs: [UUID]) {
        guard let target else { return }

        switch target {
        case .reorder(let placement):
            browserState.reorderTabs(draggedTabIDs, placement: placement)
        case .moveToFolder(let folderID, let placement):
            browserState.moveTabs(draggedTabIDs, toFolder: folderID, placement: placement)
        case .appendToFolder(let folderID):
            let placement = tailPlacement(for: folderID, excluding: draggedTabIDs)
            browserState.moveTabs(draggedTabIDs, toFolder: folderID, placement: placement)
        case .createNewFolder:
            onCreateFolder(draggedTabIDs)
        }
    }

    private func tailPlacement(for folderID: UUID?, excluding draggedTabIDs: [UUID]) -> TabInsertionPlacement {
        let draggedIDSet = Set(draggedTabIDs)
        let tailTabs = visibleTabs.filter { $0.folderID == folderID && !draggedIDSet.contains($0.id) }
        guard let lastTabID = tailTabs.last?.id else { return .end }
        return .after(lastTabID)
    }

    private func draggedOpacity(for tab: Tab) -> Double {
        guard let session = dragSession, session.draggedTabIDs.contains(tab.id) else { return 1 }
        return session.leadTabID == tab.id ? 0.96 : 0.28
    }

    private func draggedScale(for tab: Tab) -> CGFloat {
        guard let session = dragSession, session.leadTabID == tab.id else { return 1 }
        return 1.02
    }

    private func draggedOffset(for tab: Tab) -> CGSize {
        guard let session = dragSession, session.leadTabID == tab.id else { return .zero }
        return session.translation
    }

    private func dragBadgeCount(for tab: Tab) -> Int? {
        guard let session = dragSession,
              session.leadTabID == tab.id,
              session.draggedTabIDs.count > 1 else {
            return nil
        }
        return session.draggedTabIDs.count
    }

    private func zIndex(for tab: Tab) -> Double {
        guard let session = dragSession else { return 0 }
        if session.leadTabID == tab.id {
            return 10_000
        }
        if session.draggedTabIDs.contains(tab.id) {
            return 9_000
        }
        return 0
    }

    private func dropDecoration(for tab: Tab) -> some View {
        Group {
            if let hoverTarget = dragSession?.hoverTarget {
                switch hoverTarget {
                case .reorder(let placement):
                    if case .end = placement,
                       tab.id == lastDroppableTabID() {
                        insertionMarker(alignment: .bottom, accentColor: selectionTint, label: nil)
                    } else {
                        dropIndicator(for: tab, placement: placement, accentColor: selectionTint, label: nil)
                    }
                case .moveToFolder(let folderID, let placement):
                    let folderName = browserState.folder(for: folderID)?.name ?? "Group"
                    let accentColor = browserState.folder(for: folderID)?.accentColor ?? selectionTint
                    dropIndicator(
                        for: tab,
                        placement: placement,
                        accentColor: accentColor,
                        label: "Add to \(folderName)"
                    )
                case .appendToFolder, .createNewFolder:
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }

    private func lastDroppableTabID() -> UUID? {
        guard let session = dragSession else { return visibleTabs.last?.id }
        let draggedIDSet = Set(session.draggedTabIDs)
        return visibleTabs.last(where: { !draggedIDSet.contains($0.id) })?.id
    }

    @ViewBuilder
    private func dropIndicator(
        for tab: Tab,
        placement: TabInsertionPlacement,
        accentColor: Color,
        label: String?
    ) -> some View {
        switch placement {
        case .before(let tabID) where tabID == tab.id:
            insertionMarker(alignment: .top, accentColor: accentColor, label: label)
        case .after(let tabID) where tabID == tab.id:
            insertionMarker(alignment: .bottom, accentColor: accentColor, label: label)
        default:
            EmptyView()
        }
    }

    private func insertionMarker(
        alignment: Alignment,
        accentColor: Color,
        label: String?
    ) -> some View {
        ZStack(alignment: alignment) {
            Capsule(style: .continuous)
                .fill(accentColor)
                .frame(height: 4)
                .padding(.horizontal, 2)
                .offset(y: alignment == .top ? -4 : 4)

            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accentColor)
                    )
                    .shadow(color: accentColor.opacity(0.24), radius: 8, x: 0, y: 4)
                    .offset(y: alignment == .top ? -22 : 22)
            }
        }
        .allowsHitTesting(false)
    }

    private func railTargetTitle(for target: TabStripRailDropTarget) -> String {
        switch target {
        case .loose:
            return "Loose"
        case .folder(let folderID):
            return browserState.folder(for: folderID)?.name ?? "Folder"
        case .newGroup:
            return "New Group"
        }
    }

    private func railTargetSubtitle(for target: TabStripRailDropTarget) -> String {
        switch target {
        case .loose:
            return "Remove folder membership"
        case .folder:
            return "Append to group tail"
        case .newGroup:
            return "Create a folder from dragged tabs"
        }
    }

    private func railTargetColor(for target: TabStripRailDropTarget) -> Color {
        switch target {
        case .loose:
            return Color(nsColor: .systemGray)
        case .folder(let folderID):
            return browserState.folder(for: folderID)?.accentColor ?? selectionTint
        case .newGroup:
            return selectionTint
        }
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

private struct TabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TabStripRailFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TabStripRailDropTarget: CGRect] = [:]

    static func reduce(value: inout [TabStripRailDropTarget: CGRect], nextValue: () -> [TabStripRailDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SelectionClusterRect: Identifiable {
    let id = UUID()
    let rect: CGRect
}

private struct TabStripDragSession {
    let leadTabID: UUID
    let draggedTabIDs: [UUID]
    let sourceFolderID: UUID?
    let startLocation: CGPoint
    var currentLocation: CGPoint
    var translation: CGSize = .zero
    var hoverTarget: TabStripHoverTarget?
}

private enum TabStripHoverTarget: Equatable {
    case reorder(TabInsertionPlacement)
    case moveToFolder(folderID: UUID, placement: TabInsertionPlacement)
    case appendToFolder(UUID?)
    case createNewFolder

    func matches(railTarget: TabStripRailDropTarget) -> Bool {
        switch (self, railTarget) {
        case (.appendToFolder(nil), .loose):
            return true
        case (.appendToFolder(let folderID), .folder(let targetFolderID)):
            return folderID == targetFolderID
        case (.createNewFolder, .newGroup):
            return true
        default:
            return false
        }
    }
}

private enum TabStripRailDropTarget: Hashable {
    case loose
    case folder(UUID)
    case newGroup
}

private struct StageManagerHoverRegion: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> StageManagerHoverTrackingView {
        let view = StageManagerHoverTrackingView()
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: StageManagerHoverTrackingView, context: Context) {
        nsView.onHoverChange = onHoverChange
    }
}

private final class StageManagerHoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false
    private var eventMonitor: Any?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        syncHoverStateWithCurrentMouseLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            installEventMonitorIfNeeded()
        } else {
            removeEventMonitor()
        }
        syncHoverStateWithCurrentMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHoverState(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        removeEventMonitor()
    }

    private func syncHoverStateWithCurrentMouseLocation() {
        guard let window else {
            updateHoverState(false)
            return
        }

        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateHoverState(bounds.contains(point))
    }

    private func updateHoverState(_ isHovered: Bool) {
        guard isHovered != isMouseInside else { return }
        isMouseInside = isHovered
        onHoverChange?(isHovered)
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.syncHoverStateWithCurrentMouseLocation()
            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
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
