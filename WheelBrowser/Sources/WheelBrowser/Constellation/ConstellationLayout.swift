import Foundation

/// Computes 2D positions for node dots using a simple force-directed layout.
/// Runs off the main actor so the UI stays responsive during computation.
enum ConstellationLayout {

    /// Input data needed for layout, safe to send across actor boundaries.
    struct Input: Sendable {
        let nodes: [(id: String, domain: String)]
        let clusters: [(nodeIds: [String], label: String)]
        let existingPositions: [String: CGPoint]
        let canvasSize: CGSize
        let canvasCenter: CGPoint
        let zoomLevel: CGFloat
    }

    /// Compute positions for all nodes. Nodes with existing positions are fixed in place;
    /// new nodes are positioned by force simulation.
    /// This function is `nonisolated` so it can run on a background thread.
    static func layout(_ input: Input) -> [String: CGPoint] {
        let n = input.nodes.count
        guard n > 0 else { return [:] }

        let canvasCenter = input.canvasCenter
        let canvasSize = input.canvasSize

        if n == 1 {
            return [input.nodes[0].id: canvasCenter]
        }

        // Map node IDs to indices
        let indexMap: [String: Int] = Dictionary(uniqueKeysWithValues:
            input.nodes.enumerated().map { ($1.id, $0) }
        )

        // Build edge set from clusters using spanning tree (not all-pairs).
        // For each cluster, connect nodes in a chain: 0-1, 1-2, 2-3, ...
        // This reduces O(k^2) edges per cluster to O(k) while keeping the cluster connected.
        var linkedPairs = Set<IndexPair>()
        for cluster in input.clusters {
            let indices = cluster.nodeIds.compactMap { indexMap[$0] }
            guard indices.count >= 2 else { continue }
            for i in 0..<(indices.count - 1) {
                linkedPairs.insert(IndexPair(min(indices[i], indices[i + 1]),
                                             max(indices[i], indices[i + 1])))
            }
        }

        // Seed initial positions — scale radius to canvas size
        let seedRadius = min(canvasSize.width, canvasSize.height) * 0.35
        var positions: [CGPoint] = input.nodes.enumerated().map { i, node in
            if let existing = input.existingPositions[node.id] {
                return existing
            }
            let angle = Double(i) / Double(n) * 2.0 * .pi
            return CGPoint(
                x: canvasCenter.x + cos(angle) * seedRadius + sin(Double(i) * 7.0) * 15,
                y: canvasCenter.y + sin(angle) * seedRadius + cos(Double(i) * 11.0) * 15
            )
        }

        // Track which nodes are fixed (have persisted positions)
        let fixed: [Bool] = input.nodes.map { input.existingPositions[$0.id] != nil }
        let nonFixedIndices = (0..<n).filter { !fixed[$0] }

        // Skip force simulation if all nodes are fixed
        guard !nonFixedIndices.isEmpty else {
            var result: [String: CGPoint] = [:]
            for (i, node) in input.nodes.enumerated() {
                result[node.id] = positions[i]
            }
            return result
        }

        let targetLinkLength: Double = 80
        let repulsionStrength: Double = -200
        let linkStiffness: Double = 0.08
        let centerStrength: Double = 0.008
        let velocityDecay: Double = 0.55
        var velocities = Array(repeating: CGPoint.zero, count: n)
        var alpha: Double = 1.0
        let alphaDecay: Double = 0.03

        for _ in 0..<150 {
            alpha += (0 - alpha) * alphaDecay
            guard alpha > 0.01 else { break }

            // Repulsion between all pairs (1/r falloff for long-range push)
            for i in nonFixedIndices {
                for j in 0..<n where i != j {
                    var dx = positions[j].x - positions[i].x
                    var dy = positions[j].y - positions[i].y
                    // Jitter coincident nodes to avoid zero-distance singularity
                    if dx * dx + dy * dy < 1.0 {
                        dx = Double.random(in: -1...1)
                        dy = Double.random(in: -1...1)
                    }
                    let distSq = max(dx * dx + dy * dy, 1.0)
                    let dist = sqrt(distSq)
                    let force = repulsionStrength * alpha / dist
                    velocities[i].x += force * dx / dist
                    velocities[i].y += force * dy / dist
                }
            }

            // Link attraction
            for pair in linkedPairs {
                let a = pair.a, b = pair.b
                let dx = positions[b].x - positions[a].x
                let dy = positions[b].y - positions[a].y
                let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                let force = (dist - targetLinkLength) * linkStiffness * alpha
                let fx = force * dx / dist
                let fy = force * dy / dist
                if !fixed[a] {
                    velocities[a].x += fx
                    velocities[a].y += fy
                }
                if !fixed[b] {
                    velocities[b].x -= fx
                    velocities[b].y -= fy
                }
            }

            // Center pull
            for i in nonFixedIndices {
                velocities[i].x += (canvasCenter.x - positions[i].x) * centerStrength * alpha
                velocities[i].y += (canvasCenter.y - positions[i].y) * centerStrength * alpha
            }

            // Integrate velocity → position
            for i in nonFixedIndices {
                velocities[i].x *= velocityDecay
                velocities[i].y *= velocityDecay
                positions[i].x += velocities[i].x
                positions[i].y += velocities[i].y
            }
        }

        // Post-normalization: scale non-fixed nodes to fill canvas with margins.
        // Normalizes only non-fixed nodes using their own bounding box.
        if nonFixedIndices.count >= 2 {
            let margin: CGFloat = 60
            let xs = nonFixedIndices.map { positions[$0].x }
            let ys = nonFixedIndices.map { positions[$0].y }
            let minX = xs.min()!
            let maxX = xs.max()!
            let minY = ys.min()!
            let maxY = ys.max()!
            let layoutW = maxX - minX
            let layoutH = maxY - minY
            let layoutCenterX = (minX + maxX) / 2
            let layoutCenterY = (minY + maxY) / 2

            if layoutW > 1 || layoutH > 1 {
                let availW = canvasSize.width - margin * 2
                let availH = canvasSize.height - margin * 2
                let scale = min(availW / max(layoutW, 1), availH / max(layoutH, 1), 2.0)

                for i in nonFixedIndices {
                    positions[i].x = canvasCenter.x + (positions[i].x - layoutCenterX) * scale
                    positions[i].y = canvasCenter.y + (positions[i].y - layoutCenterY) * scale
                }
            }
        }

        var result: [String: CGPoint] = [:]
        for (i, node) in input.nodes.enumerated() {
            result[node.id] = positions[i]
        }
        return result
    }
}

/// Hashable pair of indices (a < b)
private struct IndexPair: Hashable {
    let a: Int
    let b: Int
    init(_ a: Int, _ b: Int) {
        self.a = a
        self.b = b
    }
}
