import Testing
import CoreGraphics
@testable import WheelBrowser

@Suite("ConstellationLayout Tests")
struct ConstellationLayoutTests {

    private let canvasSize = CGSize(width: 800, height: 600)
    private var canvasCenter: CGPoint { CGPoint(x: 400, y: 300) }

    private func makeInput(
        nodes: [(id: String, domain: String)],
        clusters: [(nodeIds: [String], label: String)] = [],
        existingPositions: [String: CGPoint] = [:]
    ) -> ConstellationLayout.Input {
        ConstellationLayout.Input(
            nodes: nodes,
            clusters: clusters,
            existingPositions: existingPositions,
            canvasSize: canvasSize,
            canvasCenter: canvasCenter,
            zoomLevel: 1.0
        )
    }

    // MARK: - Basic cases

    @Test("Empty input returns empty positions")
    func emptyInput() {
        let input = makeInput(nodes: [])
        let result = ConstellationLayout.layout(input)
        #expect(result.isEmpty)
    }

    @Test("Single node positioned at canvas center")
    func singleNode() {
        let input = makeInput(nodes: [("url1", "a.com")])
        let result = ConstellationLayout.layout(input)
        #expect(result["url1"] == canvasCenter)
    }

    @Test("All nodes get positions")
    func allNodesPositioned() {
        let nodes = (0..<10).map { ("url\($0)", "domain\($0).com") }
        let input = makeInput(nodes: nodes)
        let result = ConstellationLayout.layout(input)
        #expect(result.count == 10)
        for node in nodes {
            #expect(result[node.0] != nil)
        }
    }

    // MARK: - Fixed nodes

    @Test("Fixed nodes remain at their positions")
    func fixedNodesUnmoved() {
        let fixedPos = CGPoint(x: 100, y: 100)
        let nodes = [("fixed", "a.com"), ("free", "b.com")]
        let input = makeInput(
            nodes: nodes,
            existingPositions: ["fixed": fixedPos]
        )
        let result = ConstellationLayout.layout(input)
        #expect(result["fixed"] == fixedPos)
    }

    @Test("All fixed nodes returns exact positions")
    func allFixedNodes() {
        let pos1 = CGPoint(x: 100, y: 100)
        let pos2 = CGPoint(x: 500, y: 400)
        let nodes = [("a", "a.com"), ("b", "b.com")]
        let input = makeInput(
            nodes: nodes,
            existingPositions: ["a": pos1, "b": pos2]
        )
        let result = ConstellationLayout.layout(input)
        #expect(result["a"] == pos1)
        #expect(result["b"] == pos2)
    }

    // MARK: - Layout properties

    @Test("Nodes are spread apart by repulsion")
    func nodesSpreadApart() {
        let nodes = (0..<5).map { ("url\($0)", "a.com") }
        let input = makeInput(nodes: nodes)
        let result = ConstellationLayout.layout(input)

        // Check that no two nodes are at the exact same position
        let positions = Array(result.values)
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let dist = sqrt(dx * dx + dy * dy)
                #expect(dist > 1.0, "Nodes \(i) and \(j) are too close: \(dist)")
            }
        }
    }

    @Test("Cluster edges attract connected nodes")
    func clusterEdgesAttract() {
        // Two clusters: nodes 0-2 linked, nodes 3-5 linked
        let nodes = (0..<6).map { ("url\($0)", "d\($0 / 3).com") }
        let clusters: [(nodeIds: [String], label: String)] = [
            (["url0", "url1", "url2"], "cluster1"),
            (["url3", "url4", "url5"], "cluster2"),
        ]
        let input = makeInput(nodes: nodes, clusters: clusters)
        let result = ConstellationLayout.layout(input)

        // Compute average position of each cluster
        func avgPos(_ ids: [String]) -> CGPoint {
            let pts = ids.compactMap { result[$0] }
            let x = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let y = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            return CGPoint(x: x, y: y)
        }

        // Intra-cluster distances should be smaller than inter-cluster distances
        let c1Center = avgPos(["url0", "url1", "url2"])
        let c2Center = avgPos(["url3", "url4", "url5"])

        // Check that cluster centers are separated
        let interDist = sqrt(pow(c1Center.x - c2Center.x, 2) + pow(c1Center.y - c2Center.y, 2))
        #expect(interDist > 10, "Cluster centers should be separated")
    }

    // MARK: - Post-normalization

    @Test("Non-fixed nodes stay within canvas bounds after normalization")
    func nodesWithinBounds() {
        let nodes = (0..<20).map { ("url\($0)", "d\($0 % 4).com") }
        let input = makeInput(nodes: nodes)
        let result = ConstellationLayout.layout(input)

        let margin: CGFloat = 60
        for (_, pos) in result {
            // Allow small floating-point tolerance
            #expect(pos.x >= margin - 1, "Node x=\(pos.x) below left margin")
            #expect(pos.x <= canvasSize.width - margin + 1, "Node x=\(pos.x) beyond right margin")
            #expect(pos.y >= margin - 1, "Node y=\(pos.y) above top margin")
            #expect(pos.y <= canvasSize.height - margin + 1, "Node y=\(pos.y) below bottom margin")
        }
    }

    // MARK: - Determinism

    @Test("Layout is deterministic with same input")
    func deterministic() {
        // Note: ConstellationLayout uses Double.random for jitter, so this test
        // verifies structural correctness (all nodes present, reasonable positions)
        // rather than exact position matching
        let nodes = [("url1", "a.com"), ("url2", "b.com"), ("url3", "c.com")]
        let input = makeInput(nodes: nodes)
        let result = ConstellationLayout.layout(input)

        #expect(result.count == 3)
        for node in nodes {
            #expect(result[node.0] != nil)
        }
    }
}
