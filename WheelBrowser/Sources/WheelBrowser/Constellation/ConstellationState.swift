import SwiftUI
import Combine
import AppKit

/// A single node in the Constellation — either a history entry or a search result
struct ConstellationNode: Identifiable, Equatable {
    let id: String          // URL string (stable identity)
    let url: URL
    let title: String
    let domain: String      // host without "www."
    let timestamp: Date?    // non-nil for history
    let searchScore: Float? // non-nil for search results
    var summary: String?    // populated from DIndex cluster response
    var snippet: String?    // populated from DIndex cluster response

    init(id: String, url: URL, title: String, domain: String, timestamp: Date? = nil, searchScore: Float? = nil, summary: String? = nil, snippet: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.domain = domain
        self.timestamp = timestamp
        self.searchScore = searchScore
        self.summary = summary
        self.snippet = snippet
    }

    init(from entry: HistoryEntry) {
        let parsedURL = URL(string: entry.url) ?? URL(string: "about:blank")!
        let host = parsedURL.host ?? ""
        self.id = entry.url
        self.url = parsedURL
        self.title = entry.title
        self.domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        self.timestamp = entry.timestamp
        self.searchScore = nil
    }

    init(from item: DIndexSearchItem) {
        let urlString = item.url ?? item.id
        let parsedURL = URL(string: urlString) ?? URL(string: "about:blank")!
        let host = parsedURL.host ?? ""
        self.id = urlString
        self.url = parsedURL
        self.title = item.title ?? urlString
        self.domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        self.timestamp = nil
        self.searchScore = item.score
    }
}

/// Describes a group of related nodes
struct ConstellationCluster: Identifiable {
    let id: String          // deterministic, based on label (domain name)
    let nodeIds: [String]
    let label: String
    let color: Color
    let topDomains: [String]  // top 3 domains in this cluster

    static let clusterColors: [Color] = [
        .blue,
        .green,
        .orange,
        .purple,
        .pink,
        .teal,
        .yellow,
        .red,
        .cyan,
        .mint,
        .indigo,
        .brown,
        .gray,
        .orange,
        .blue,
        .green,
    ]
}

/// Current display mode of the Constellation
enum ConstellationMode {
    case history
    case search
}

/// Observable state for the Constellation canvas overlay
@MainActor
final class ConstellationState: ObservableObject {
    static let shared = ConstellationState()

    @Published var isVisible = false
    @Published var nodes: [ConstellationNode] = []
    @Published var nodePositions: [String: CGPoint] = [:]
    @Published var clusters: [ConstellationCluster] = []
    @Published var zoom: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var searchQuery: String = ""
    @Published var isLoading = false
    @Published var mode: ConstellationMode = .history

    /// Dictionary for O(1) node lookup by ID.
    /// Not @Published — only used for hover card lookup, avoids extra objectWillChange.
    var nodeDict: [String: ConstellationNode] = [:]

    /// Current canvas size from GeometryReader (used for dynamic center)
    var canvasSize: CGSize = CGSize(width: 1200, height: 800)

    /// ID of the card currently being dragged (prevents canvas pan during card drag)
    var draggedCardId: String?

    /// Cancellable for the debounced search pipeline
    var searchCancellable: AnyCancellable?

    /// Subject for debounced search queries
    let searchDebounceSubject = PassthroughSubject<String, Never>()

    /// Cancellable for debounced zoom re-layout
    var zoomLayoutCancellable: AnyCancellable?

    /// Cancellable for debounced resize re-layout
    var resizeLayoutCancellable: AnyCancellable?

    /// Active search task for cooperative cancellation
    var searchTask: Task<Void, Never>?

    /// Escape key event monitor
    var escapeMonitor: Any?

    /// The zoom level at which the last layout was computed
    var layoutZoom: CGFloat = 1.0

    /// Saved history positions to restore when clearing search
    var savedHistoryPositions: [String: CGPoint] = [:]

    /// Saved history zoom/offset to restore when clearing search
    var savedHistoryZoom: CGFloat = 1.0
    var savedHistoryOffset: CGSize = .zero

    func show() {
        withAnimation(AppAnimation.panelSpring) {
            isVisible = true
        }
    }

    func dismiss() {
        // Non-animated cleanup BEFORE the animated visibility change (CLAUDE.md Rule 8).
        // @Published mutations fire objectWillChange without an animation context;
        // if they fire after the withAnimation they cause non-animated body re-evals
        // that interleave with the transition animation.
        searchQuery = ""
        searchCancellable?.cancel()
        searchCancellable = nil
        zoomLayoutCancellable?.cancel()
        zoomLayoutCancellable = nil
        resizeLayoutCancellable?.cancel()
        resizeLayoutCancellable = nil
        searchTask?.cancel()
        searchTask = nil
        savedHistoryPositions.removeAll()
        savedHistoryZoom = 1.0
        savedHistoryOffset = .zero
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        withAnimation(AppAnimation.panelSpring) {
            isVisible = false
        }
    }

    /// Atomically sets nodes and nodeDict in sync
    func setNodes(_ newNodes: [ConstellationNode]) {
        nodes = newNodes
        nodeDict = Dictionary(newNodes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func reset() {
        isLoading = true  // Set BEFORE clearing nodes to prevent flash of "No browsing history"
        nodes.removeAll()
        nodeDict.removeAll()
        nodePositions.removeAll()
        clusters.removeAll()
        zoom = 1.0
        offset = .zero
        searchQuery = ""
        mode = .history
        canvasSize = CGSize(width: 1200, height: 800)
        draggedCardId = nil
        searchCancellable?.cancel()
        searchCancellable = nil
        zoomLayoutCancellable?.cancel()
        zoomLayoutCancellable = nil
        resizeLayoutCancellable?.cancel()
        resizeLayoutCancellable = nil
        searchTask?.cancel()
        searchTask = nil
        layoutZoom = 1.0
        savedHistoryPositions.removeAll()
        savedHistoryZoom = 1.0
        savedHistoryOffset = .zero
    }

    /// Apply scroll-wheel zoom centered on the cursor position.
    /// Adjusts offset so the content point under the cursor stays fixed.
    /// `cursorInCanvas` is already in SwiftUI top-left coordinate space.
    func applyScrollZoom(factor: CGFloat, cursorInCanvas: CGPoint, canvasSize: CGSize) {
        let oldZoom = zoom
        let newZoom = max(0.3, min(3.0, oldZoom * factor))
        guard newZoom != oldZoom else { return }

        let cursorX = cursorInCanvas.x
        let cursorY = cursorInCanvas.y

        // The cursor's position in content space before zoom
        let canvasCenterX = canvasSize.width / 2
        let canvasCenterY = canvasSize.height / 2
        let contentX = (cursorX - canvasCenterX - offset.width) / oldZoom
        let contentY = (cursorY - canvasCenterY - offset.height) / oldZoom

        // After zoom, the same content point should stay under the cursor
        let newOffsetW = cursorX - canvasCenterX - contentX * newZoom
        let newOffsetH = cursorY - canvasCenterY - contentY * newZoom

        zoom = newZoom
        offset = CGSize(width: newOffsetW, height: newOffsetH)
    }
}
