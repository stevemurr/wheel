import SwiftUI
import Combine
import AppKit

/// Full-screen overlay showing browsing history (or search results) as cards
/// on a zoomable/pannable canvas, clustered by domain.
struct ConstellationView: View {
    @ObservedObject var state: ConstellationState
    @ObservedObject var browserState: BrowserState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            // Dark backdrop — tap to dismiss
            Color.black.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture { state.dismiss() }

            // Canvas
            ConstellationCanvas(
                state: state,
                onSelectNode: { node in
                    browserState.navigate(to: node.url)
                    state.dismiss()
                },
                onZoomChanged: { scheduleZoomRelayout() },
                onCanvasSizeChanged: { _ in
                    scheduleResizeRelayout()
                }
            )

            // Search bar at top
            VStack {
                searchBar
                    .padding(.top, 20)
                Spacer()
            }

            // Empty state
            if state.nodes.isEmpty && !state.isLoading {
                Text("No browsing history")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            // Loading indicator
            if state.isLoading {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(state.mode == .search ? "Searching..." : "Loading history...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 20)
                }
            }
        }
        .onExitCommand { state.dismiss() }
        .onAppear {
            loadHistoryConstellation()
            installEscapeMonitor()
            installSearchDebounce()
        }
        .onDisappear {
            savePositions()
            removeEscapeMonitor()
        }
        .onChange(of: state.searchQuery) { _, newQuery in
            handleSearchQueryChange(newQuery)
        }
        .onChange(of: browserState.currentWorkspaceId) { _, _ in
            loadHistoryConstellation()
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history...", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 400)
    }

    // MARK: - History loading

    /// Build deduplicated, capped history nodes from BrowsingHistory.
    private func buildHistoryNodes() -> [ConstellationNode] {
        let entries = BrowsingHistory.shared.entries
        var seen = Set<String>()
        var nodes: [ConstellationNode] = []
        for entry in entries {
            guard !seen.contains(entry.url) else { continue }
            seen.insert(entry.url)
            nodes.append(ConstellationNode(from: entry))
            if nodes.count >= 200 { break }
        }
        return nodes
    }

    private func loadHistoryConstellation() {
        state.reset()

        // Set up persistence for current workspace
        ConstellationPersistence.shared.setWorkspace(browserState.currentWorkspaceId)

        let nodes = buildHistoryNodes()

        state.setNodes(nodes)
        state.mode = .history

        // Load persisted positions (user-dragged only)
        var persistedPositions: [String: CGPoint] = [:]
        for node in nodes {
            if let pos = ConstellationPersistence.shared.loadPosition(for: node.url) {
                persistedPositions[node.id] = pos
                state.nodePositions[node.id] = pos
            }
        }

        // Run clustering + layout (persisted positions are fixed, rest are computed)
        runClusteringAndLayout(for: nodes, existingPositions: persistedPositions)
    }

    // MARK: - Search

    private func handleSearchQueryChange(_ query: String) {
        state.searchTask?.cancel()

        guard !query.isEmpty else {
            clearSearch()
            return
        }

        state.searchDebounceSubject.send(query)
    }

    /// Call once to wire up the debounced search pipeline.
    private func installSearchDebounce() {
        state.searchCancellable = state.searchDebounceSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [state] debouncedQuery in
                state.searchTask?.cancel()
                state.searchTask = Task { @MainActor in
                    await performSearch(query: debouncedQuery)
                }
            }
    }

    @MainActor
    private func performSearch(query: String) async {
        // Guard stale/cancelled queries
        guard !Task.isCancelled, query == state.searchQuery else { return }

        state.isLoading = true
        state.mode = .search

        // Save history positions/zoom/offset before replacing
        if state.savedHistoryPositions.isEmpty {
            state.savedHistoryPositions = state.nodePositions
            state.savedHistoryZoom = state.zoom
            state.savedHistoryOffset = state.offset
        }

        var resultNodes: [ConstellationNode] = []

        // Try DIndex first
        let settings = AppSettings.shared
        if settings.dindexEnabled,
           let service = SemanticSearchManagerV2.shared.dIndexService {
            do {
                let results = try await service.search(query: query, limit: 100)
                // Guard stale after await
                guard query == state.searchQuery else { return }
                resultNodes = results.map { ConstellationNode(from: $0) }
            } catch {
                // Fall through to history search
            }
        }

        // Fallback to BrowsingHistory fuzzy search
        if resultNodes.isEmpty {
            let historyResults = BrowsingHistory.shared.search(query: query, limit: 100)
            // Guard stale after potential async
            guard query == state.searchQuery else { return }
            resultNodes = historyResults.map { ConstellationNode(from: $0) }
        }

        // Deduplicate by URL
        var seen = Set<String>()
        resultNodes = resultNodes.filter { node in
            guard !seen.contains(node.id) else { return false }
            seen.insert(node.id)
            return true
        }

        // Replace constellation — don't removeAll() positions first to avoid
        // nodes vanishing then reappearing (#13). New positions overwrite old.
        state.setNodes(resultNodes)

        runClusteringAndLayout(for: resultNodes, existingPositions: [:])
        state.isLoading = false
    }

    private func clearSearch() {
        guard state.mode == .search || !state.searchQuery.isEmpty else { return }

        // Don't destroy the debounce pipeline — just clear the query.
        // The pipeline installed by installSearchDebounce() will handle the empty
        // string naturally. Destroying it (#1) would break search permanently
        // until the constellation is dismissed and reopened.
        state.searchQuery = ""

        // Restore history view with persisted positions, zoom, and offset
        state.mode = .history

        let nodes = buildHistoryNodes()

        state.setNodes(nodes)
        state.nodePositions = state.savedHistoryPositions
        state.zoom = state.savedHistoryZoom
        state.offset = state.savedHistoryOffset
        state.savedHistoryPositions.removeAll()

        runClusteringAndLayout(for: nodes, existingPositions: state.nodePositions)
    }

    // MARK: - Clustering + Layout

    /// Run domain-based clustering immediately, then attempt semantic clustering async.
    /// `existingPositions` controls which nodes are fixed — pass only user-dragged/persisted
    /// positions, NOT all current positions (otherwise relayout is a no-op, #3).
    private func runClusteringAndLayout(
        for nodes: [ConstellationNode],
        existingPositions: [String: CGPoint]? = nil
    ) {
        // Phase 1: immediate domain-based clusters
        let clusters = ConstellationClusterer.clusterByDomain(nodes: nodes)
        applyLayout(nodes: nodes, clusters: clusters, existingPositions: existingPositions)

        // Phase 2: semantic clusters from DIndex (async upgrade)
        requestSemanticClustering(for: nodes, existingPositions: existingPositions)
    }

    /// Compute force-directed layout on a background thread and apply results.
    private func applyLayout(
        nodes: [ConstellationNode],
        clusters: [ConstellationCluster],
        existingPositions: [String: CGPoint]? = nil
    ) {
        let canvasCenter = CGPoint(x: state.canvasSize.width / 2, y: state.canvasSize.height / 2)

        let input = ConstellationLayout.Input(
            nodes: nodes.map { ($0.id, $0.domain) },
            clusters: clusters.map { ($0.nodeIds, $0.label) },
            existingPositions: existingPositions ?? state.nodePositions,
            canvasSize: state.canvasSize,
            canvasCenter: canvasCenter,
            zoomLevel: state.zoom
        )

        state.isLoading = true

        // Run layout off the main thread to avoid blocking the UI (#6)
        Task.detached {
            let positions = ConstellationLayout.layout(input)

            await MainActor.run {
                state.layoutZoom = state.zoom

                // Set clusters inside withAnimation so backgrounds animate
                // alongside dots (#9)
                withAnimation(AppAnimation.panelSpring) {
                    state.clusters = clusters
                    state.nodePositions = positions
                }
                state.isLoading = false
            }
        }
    }

    /// Phase 2: request semantic clusters from DIndex and smoothly transition.
    /// Silent failure — domain clusters remain if DIndex call fails or is unavailable.
    private func requestSemanticClustering(
        for nodes: [ConstellationNode],
        existingPositions: [String: CGPoint]? = nil
    ) {
        let settings = AppSettings.shared
        guard settings.dindexEnabled,
              let service = SemanticSearchManagerV2.shared.dIndexService else { return }

        let urls = nodes.map { $0.url.absoluteString }
        let currentMode = state.mode
        let nodeCount = nodes.count

        Task { @MainActor in
            do {
                let response = try await service.clusterDocuments(urls: urls)

                // Guard stale response: mode or node count changed during await
                guard state.mode == currentMode,
                      state.nodes.count == nodeCount else { return }

                // Build semantic clusters
                let semanticClusters = ConstellationClusterer.clusterFromDIndex(
                    response: response,
                    allNodes: state.nodes
                )

                // Populate node summaries from response (non-@Published nodeDict, no spurious re-renders)
                for (urlString, docSummary) in response.documents {
                    if var node = state.nodeDict[urlString] {
                        node.summary = docSummary.summary
                        node.snippet = docSummary.snippet
                        state.nodeDict[urlString] = node
                    }
                }

                // Apply layout with semantic clusters (animated transition)
                applyLayout(
                    nodes: state.nodes,
                    clusters: semanticClusters,
                    existingPositions: existingPositions
                )
            } catch {
                // Silent failure — domain clusters remain
                Log.Search.debug("Semantic clustering unavailable: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Zoom Re-layout

    private func scheduleZoomRelayout() {
        state.zoomLayoutCancellable?.cancel()

        let ratio = state.zoom / max(state.layoutZoom, 0.01)
        let significantChange = ratio > 1.3 || ratio < 0.77
        let debounceMs = significantChange ? 300 : 500

        // Skip minor zoom changes
        guard significantChange || ratio > 1.15 || ratio < 0.87 else { return }

        state.zoomLayoutCancellable = Just(())
            .delay(for: .milliseconds(debounceMs), scheduler: DispatchQueue.main)
            .sink { _ in
                relayoutForCurrentZoom()
            }
    }

    /// Re-layout with empty existing positions so the force simulation actually runs (#3).
    private func relayoutForCurrentZoom() {
        let nodes = state.nodes
        guard !nodes.isEmpty else { return }

        runClusteringAndLayout(for: nodes, existingPositions: [:])
    }

    // MARK: - Escape Key Monitor

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        state.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard state.isVisible else { return event }
            // Escape to dismiss
            if event.keyCode == 53 {
                state.dismiss()
                return nil
            }
            // Cmd+F to focus search (#19)
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f" {
                isSearchFocused = true
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = state.escapeMonitor {
            NSEvent.removeMonitor(monitor)
            state.escapeMonitor = nil
        }
    }

    // MARK: - Resize Re-layout

    /// Re-layout on resize with empty existing positions so nodes fill the new canvas (#3).
    private func scheduleResizeRelayout() {
        state.resizeLayoutCancellable?.cancel()
        guard !state.nodes.isEmpty else { return }

        state.resizeLayoutCancellable = Just(())
            .delay(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { _ in
                runClusteringAndLayout(for: state.nodes, existingPositions: [:])
            }
    }

    // MARK: - Persistence

    private func savePositions() {
        guard state.mode == .history else { return }
        ConstellationPersistence.shared.saveAll(
            nodePositions: state.nodePositions,
            nodes: state.nodes
        )
    }
}
