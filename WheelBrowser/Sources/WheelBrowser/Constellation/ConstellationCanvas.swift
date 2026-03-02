import SwiftUI

/// Zoomable, pannable canvas that displays node dots and cluster backgrounds
struct ConstellationCanvas: View {
    @ObservedObject var state: ConstellationState
    let onSelectNode: (ConstellationNode) -> Void
    var onZoomChanged: () -> Void = {}
    var onCanvasSizeChanged: ((CGSize) -> Void)?

    @State private var panAnchor: CGSize = .zero
    @State private var isPanning = false
    @GestureState private var liveMagnification: CGFloat = 1.0
    @State private var hoveredNodeId: String?
    @State private var dragStartPosition: CGPoint?
    @State private var doubleClickMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Zoomed content layer
                ZStack {
                    // Cluster backgrounds
                    ForEach(state.clusters) { cluster in
                        ClusterBackground(
                            cluster: cluster,
                            positions: state.nodePositions
                        )
                    }

                    // Node dots
                    ForEach(state.nodes) { node in
                        dotView(for: node)
                    }
                }
                .scaleEffect(state.zoom * liveMagnification, anchor: .center)
                .offset(state.offset)

                // Non-zoomed hover card overlay (constant size regardless of zoom)
                if let hId = hoveredNodeId,
                   let node = state.nodeDict[hId],
                   let pos = state.nodePositions[hId] {
                    let currentZoom = state.zoom * liveMagnification
                    let centerX = geo.size.width / 2
                    let centerY = geo.size.height / 2
                    let screenX = centerX + (pos.x - centerX) * currentZoom + state.offset.width
                    let screenY = centerY + (pos.y - centerY) * currentZoom + state.offset.height
                    let hoverY = screenY < 160 ? screenY + 90 : screenY - 90
                    let cluster = state.clusters.first { $0.nodeIds.contains(hId) }
                    ConstellationHoverCard(
                        node: node,
                        clusterLabel: cluster?.label,
                        clusterColor: cluster?.color,
                        clusterNodeCount: cluster.map { $0.nodeIds.count },
                        clusterTopDomains: cluster?.topDomains,
                        summary: node.summary ?? node.snippet
                    )
                        .position(x: screenX, y: hoverY)
                        .allowsHitTesting(false)
                }

                // Non-zoomed cluster label overlay (constant size during zoom)
                ClusterLabelOverlay(
                    clusters: state.clusters,
                    positions: state.nodePositions,
                    zoom: state.zoom * liveMagnification,
                    offset: state.offset,
                    canvasSize: geo.size
                )
                .allowsHitTesting(false)
            }
            // Canvas pan (child gestures like card drag take priority)
            .gesture(canvasPanGesture)
            // Pinch zoom
            .gesture(zoomGesture)
            .background {
                ConstellationScrollZoomView(
                    state: state,
                    onZoomChanged: onZoomChanged
                )
            }
            .onAppear {
                state.canvasSize = geo.size
                installDoubleClickMonitor()
            }
            .onDisappear {
                removeDoubleClickMonitor()
            }
            .onChange(of: geo.size) { _, newSize in
                state.canvasSize = newSize
                onCanvasSizeChanged?(newSize)
            }
            .onChange(of: state.nodes) { _, _ in
                hoveredNodeId = nil
            }
        }
    }

    // MARK: - Dot

    @ViewBuilder
    private func dotView(for node: ConstellationNode) -> some View {
        let pos = state.nodePositions[node.id] ?? .zero

        ConstellationCard(node: node)
            .position(x: pos.x, y: pos.y)
            .onHover { isHovering in
                hoveredNodeId = isHovering ? node.id : nil
            }
            .gesture(cardDragGesture(for: node))
            .onTapGesture { onSelectNode(node) }
            .contextMenu { cardContextMenu(for: node) }
    }

    // MARK: - Gestures

    private func cardDragGesture(for node: ConstellationNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if state.draggedCardId != node.id {
                    // First onChanged — capture stable anchor position
                    state.draggedCardId = node.id
                    dragStartPosition = state.nodePositions[node.id] ?? .zero
                }
                guard let start = dragStartPosition else { return }
                let newPos = CGPoint(
                    x: start.x + value.translation.width / state.zoom,
                    y: start.y + value.translation.height / state.zoom
                )
                state.nodePositions[node.id] = newPos
            }
            .onEnded { _ in
                state.draggedCardId = nil
                dragStartPosition = nil
                if state.mode == .history, let pos = state.nodePositions[node.id] {
                    ConstellationPersistence.shared.savePosition(url: node.url, position: pos)
                }
            }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard state.draggedCardId == nil else { return }
                if !isPanning {
                    panAnchor = state.offset
                    isPanning = true
                }
                let raw = CGSize(
                    width: panAnchor.width + value.translation.width,
                    height: panAnchor.height + value.translation.height
                )
                state.offset = clampedOffset(raw)
            }
            .onEnded { _ in
                isPanning = false
                // Always update panAnchor so the next pan starts from the current offset,
                // even if the gesture was suppressed by a card drag.
                panAnchor = state.offset
            }
    }

    /// Clamp offset so content stays at least partially visible within the viewport.
    private func clampedOffset(_ raw: CGSize) -> CGSize {
        let currentZoom = state.zoom * liveMagnification
        let contentHalf = max(state.canvasSize.width, state.canvasSize.height) * currentZoom * 0.5
        let maxOffset = contentHalf + 200
        return CGSize(
            width: min(max(raw.width, -maxOffset), maxOffset),
            height: min(max(raw.height, -maxOffset), maxOffset)
        )
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($liveMagnification) { value, gestureState, _ in
                // Clamp so visual zoom stays within [0.3, 3.0] during the gesture
                let raw = value.magnification
                let clamped = max(0.3 / max(state.zoom, 0.01), min(3.0 / max(state.zoom, 0.01), raw))
                gestureState = clamped
            }
            .onEnded { value in
                state.zoom = max(0.3, min(3.0, state.zoom * value.magnification))
                onZoomChanged()
            }
    }

    // MARK: - Double-click reset (uses NSEvent to avoid 300ms single-tap delay)

    private func installDoubleClickMonitor() {
        removeDoubleClickMonitor()
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [state] event in
            guard event.clickCount == 2, state.isVisible else { return event }
            withAnimation(AppAnimation.panelSpring) {
                state.zoom = 1.0
                state.offset = .zero
            }
            onZoomChanged()
            return event
        }
    }

    private func removeDoubleClickMonitor() {
        if let monitor = doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
            doubleClickMonitor = nil
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func cardContextMenu(for node: ConstellationNode) -> some View {
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.absoluteString, forType: .string)
        }
    }
}

// MARK: - Cluster Background

private struct ClusterBackground: View {
    let cluster: ConstellationCluster
    let positions: [String: CGPoint]

    var body: some View {
        let pts = cluster.nodeIds.compactMap { positions[$0] }
        if pts.count >= 1, let bounds = clusterBounds(pts) {
            if pts.count == 1 {
                Circle()
                    .fill(cluster.color.opacity(0.15))
                    .opacity(0.8)
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
            } else {
                Capsule()
                    .fill(cluster.color.opacity(0.15))
                    .opacity(0.8)
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
            }
        }
    }

    private func clusterBounds(_ points: [CGPoint]) -> CGRect? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return nil }

        let padding: CGFloat = 14
        let dotS = ConstellationCard.dotSize
        return CGRect(
            x: minX - dotS / 2 - padding,
            y: minY - dotS / 2 - padding,
            width: maxX - minX + dotS + padding * 2,
            height: maxY - minY + dotS + padding * 2
        )
    }
}

// MARK: - Cluster Label Overlay (non-zoomed)

private struct ClusterLabelInfo {
    let label: String
    let centroid: CGPoint  // world-space centroid
    let clusterId: String
    let color: Color
    let nodeCount: Int
}

/// Renders cluster labels at constant screen-space size, resolving overlaps.
private struct ClusterLabelOverlay: View {
    let clusters: [ConstellationCluster]
    let positions: [String: CGPoint]
    let zoom: CGFloat
    let offset: CGSize
    let canvasSize: CGSize

    var body: some View {
        let resolvedLabels = resolvedLabelPositions()
        ZStack {
            ForEach(resolvedLabels, id: \.clusterId) { info in
                ClusterLabelBadge(label: info.label, color: info.color, nodeCount: info.nodeCount)
                    .position(info.centroid)
            }
        }
    }

    private func resolvedLabelPositions() -> [ClusterLabelInfo] {
        let filtered = clusters.filter { $0.nodeIds.count >= 2 }
        let canvasCenterX = canvasSize.width / 2
        let canvasCenterY = canvasSize.height / 2

        var labels: [ClusterLabelInfo] = filtered.compactMap { cluster in
            let pts = cluster.nodeIds.compactMap { positions[$0] }
            guard pts.count >= 1 else { return nil }

            // World-space centroid
            let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)

            // Convert to screen-space (must match scaleEffect(zoom, anchor: .center) + offset)
            let screenX = canvasCenterX + (cx - canvasCenterX) * zoom + offset.width
            let screenY = canvasCenterY + (cy - canvasCenterY) * zoom + offset.height

            return ClusterLabelInfo(
                label: cluster.label,
                centroid: CGPoint(x: screenX, y: screenY),
                clusterId: cluster.id,
                color: cluster.color,
                nodeCount: cluster.nodeIds.count
            )
        }

        // Overlap resolution: check all pairs within proximity, nudge apart
        let labelHeight: CGFloat = 28
        let proximityX: CGFloat = 120
        guard labels.count >= 2 else { return labels }
        for _ in 0..<8 {
            labels.sort { $0.centroid.y < $1.centroid.y }
            for i in 0..<labels.count {
                for j in (i + 1)..<labels.count {
                    // Early exit: if Y gap is already large enough, skip remaining j
                    guard labels[j].centroid.y - labels[i].centroid.y < labelHeight * 2 else { break }
                    let dy = labels[j].centroid.y - labels[i].centroid.y
                    let dx = abs(labels[j].centroid.x - labels[i].centroid.x)
                    if dy < labelHeight && dx < proximityX {
                        let pushY = (labelHeight - dy) / 2 + 2
                        let pushX: CGFloat = dx < 40 ? 20 : 0
                        labels[i] = ClusterLabelInfo(
                            label: labels[i].label,
                            centroid: CGPoint(
                                x: labels[i].centroid.x - pushX,
                                y: labels[i].centroid.y - pushY
                            ),
                            clusterId: labels[i].clusterId,
                            color: labels[i].color,
                            nodeCount: labels[i].nodeCount
                        )
                        labels[j] = ClusterLabelInfo(
                            label: labels[j].label,
                            centroid: CGPoint(
                                x: labels[j].centroid.x + pushX,
                                y: labels[j].centroid.y + pushY
                            ),
                            clusterId: labels[j].clusterId,
                            color: labels[j].color,
                            nodeCount: labels[j].nodeCount
                        )
                    }
                }
            }
        }

        // Clamp labels to screen bounds
        let marginH: CGFloat = 60
        let marginV: CGFloat = 14
        for i in labels.indices {
            let x = min(max(labels[i].centroid.x, marginH), canvasSize.width - marginH)
            let y = min(max(labels[i].centroid.y, marginV), canvasSize.height - marginV)
            labels[i] = ClusterLabelInfo(
                label: labels[i].label,
                centroid: CGPoint(x: x, y: y),
                clusterId: labels[i].clusterId,
                color: labels[i].color,
                nodeCount: labels[i].nodeCount
            )
        }

        return labels
    }
}

private struct ClusterLabelBadge: View {
    let label: String
    let color: Color
    let nodeCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(nodeCount)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(color.opacity(0.55))
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.7), lineWidth: 0.5)
                }
        }
        .allowsHitTesting(false)
    }
}
