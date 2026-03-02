import Testing
import SwiftUI
@testable import WheelBrowser

@Suite("ConstellationClusterer Tests")
struct ConstellationClustererTests {

    // MARK: - Helpers

    private func makeNode(url: String, title: String = "", domain: String = "") -> ConstellationNode {
        ConstellationNode(
            id: url,
            url: URL(string: url) ?? URL(string: "about:blank")!,
            title: title,
            domain: domain
        )
    }

    // MARK: - clusterByDomain

    @Test("Empty nodes returns empty clusters")
    func domainClusterEmpty() {
        let clusters = ConstellationClusterer.clusterByDomain(nodes: [])
        #expect(clusters.isEmpty)
    }

    @Test("Single node creates single cluster")
    func domainClusterSingle() {
        let nodes = [makeNode(url: "https://example.com", domain: "example.com")]
        let clusters = ConstellationClusterer.clusterByDomain(nodes: nodes)
        #expect(clusters.count == 1)
        #expect(clusters[0].label == "example.com")
        #expect(clusters[0].nodeIds.count == 1)
    }

    @Test("Nodes grouped by domain")
    func domainClusterGrouping() {
        let nodes = [
            makeNode(url: "https://a.com/1", domain: "a.com"),
            makeNode(url: "https://a.com/2", domain: "a.com"),
            makeNode(url: "https://b.com/1", domain: "b.com"),
        ]
        let clusters = ConstellationClusterer.clusterByDomain(nodes: nodes)
        #expect(clusters.count == 2)
        // Larger cluster first
        #expect(clusters[0].label == "a.com")
        #expect(clusters[0].nodeIds.count == 2)
        #expect(clusters[1].label == "b.com")
        #expect(clusters[1].nodeIds.count == 1)
    }

    @Test("Empty domain falls back to Other")
    func domainClusterEmptyDomain() {
        let nodes = [makeNode(url: "about:blank", domain: "")]
        let clusters = ConstellationClusterer.clusterByDomain(nodes: nodes)
        #expect(clusters[0].label == "Other")
    }

    @Test("Clusters sorted by size then alphabetically")
    func domainClusterSorting() {
        let nodes = [
            makeNode(url: "https://z.com/1", domain: "z.com"),
            makeNode(url: "https://a.com/1", domain: "a.com"),
            makeNode(url: "https://a.com/2", domain: "a.com"),
            makeNode(url: "https://z.com/2", domain: "z.com"),
            makeNode(url: "https://m.com/1", domain: "m.com"),
        ]
        let clusters = ConstellationClusterer.clusterByDomain(nodes: nodes)
        // a.com and z.com tie at 2, alphabetical: a.com first
        #expect(clusters[0].label == "a.com")
        #expect(clusters[1].label == "z.com")
        #expect(clusters[2].label == "m.com")
    }

    @Test("Color cycling wraps around")
    func domainClusterColorCycling() {
        // Create more clusters than colors
        let colorCount = ConstellationCluster.clusterColors.count
        var nodes: [ConstellationNode] = []
        for i in 0..<(colorCount + 2) {
            nodes.append(makeNode(url: "https://domain\(i).com", domain: "domain\(i).com"))
        }
        let clusters = ConstellationClusterer.clusterByDomain(nodes: nodes)
        #expect(clusters.count == colorCount + 2)
        // Last clusters should wrap color index
        #expect(clusters[colorCount].color == clusters[0].color)
    }

    // MARK: - clusterFromDIndex

    @Test("DIndex clusters use generated labels from titles")
    func dindexClusterLabels() {
        let nodes = [
            makeNode(url: "https://a.com/swift-guide", title: "Swift Programming Guide", domain: "a.com"),
            makeNode(url: "https://b.com/swift-tutorial", title: "Swift Tutorial for Beginners", domain: "b.com"),
            makeNode(url: "https://c.com/swift-docs", title: "Swift Documentation Reference", domain: "c.com"),
        ]
        let response = ClusterResponse(
            clusters: [
                DocumentCluster(
                    clusterId: "c1",
                    label: "Announces Anyone",  // meaningless API label
                    documentUrls: ["https://a.com/swift-guide", "https://b.com/swift-tutorial", "https://c.com/swift-docs"]
                )
            ],
            documents: [
                "https://a.com/swift-guide": DocumentSummary(title: "Swift Programming Guide", snippet: ""),
                "https://b.com/swift-tutorial": DocumentSummary(title: "Swift Tutorial for Beginners", snippet: ""),
                "https://c.com/swift-docs": DocumentSummary(title: "Swift Documentation Reference", snippet: ""),
            ],
            unmatchedUrls: [],
            clusterTimeMs: 100
        )

        let clusters = ConstellationClusterer.clusterFromDIndex(response: response, allNodes: nodes)
        #expect(clusters.count == 1)
        // Should NOT be the raw API label
        #expect(clusters[0].label != "Announces Anyone")
        // Should contain "Swift" as the most common word
        #expect(clusters[0].label.contains("Swift"))
    }

    @Test("Unmatched nodes fall back to domain clusters")
    func dindexUnmatchedFallback() {
        let nodes = [
            makeNode(url: "https://a.com/1", title: "Page A", domain: "a.com"),
            makeNode(url: "https://b.com/1", title: "Page B", domain: "b.com"),
        ]
        let response = ClusterResponse(
            clusters: [
                DocumentCluster(clusterId: "c1", label: "Test", documentUrls: ["https://a.com/1"])
            ],
            documents: [:],
            unmatchedUrls: ["https://b.com/1"],
            clusterTimeMs: 50
        )

        let clusters = ConstellationClusterer.clusterFromDIndex(response: response, allNodes: nodes)
        #expect(clusters.count == 2)
        // Second cluster is the domain fallback
        #expect(clusters[1].id == "fallback_b.com")
        #expect(clusters[1].label == "b.com")
    }

    @Test("DIndex cluster with no matching nodes is skipped")
    func dindexSkipsEmptyClusters() {
        let nodes = [makeNode(url: "https://a.com/1", domain: "a.com")]
        let response = ClusterResponse(
            clusters: [
                DocumentCluster(clusterId: "c1", label: "Ghost", documentUrls: ["https://nonexistent.com/page"])
            ],
            documents: [:],
            unmatchedUrls: [],
            clusterTimeMs: 10
        )

        let clusters = ConstellationClusterer.clusterFromDIndex(response: response, allNodes: nodes)
        // The ghost cluster is skipped, node falls back to domain cluster
        let dindexClusters = clusters.filter { !$0.id.hasPrefix("fallback_") }
        #expect(dindexClusters.isEmpty)
    }

    @Test("Label falls back to topDomains when no titles")
    func dindexLabelFallbackToDomain() {
        let nodes = [
            makeNode(url: "https://a.com/1", title: "", domain: "a.com"),
            makeNode(url: "https://a.com/2", title: "", domain: "a.com"),
        ]
        let response = ClusterResponse(
            clusters: [
                DocumentCluster(clusterId: "c1", label: "Raw Label", documentUrls: ["https://a.com/1", "https://a.com/2"])
            ],
            documents: [:],
            unmatchedUrls: [],
            clusterTimeMs: 10
        )

        let clusters = ConstellationClusterer.clusterFromDIndex(response: response, allNodes: nodes)
        #expect(clusters[0].label == "a.com")
    }

    @Test("Top domains computed correctly")
    func dindexTopDomains() {
        let nodes = [
            makeNode(url: "https://a.com/1", domain: "a.com"),
            makeNode(url: "https://a.com/2", domain: "a.com"),
            makeNode(url: "https://b.com/1", domain: "b.com"),
            makeNode(url: "https://c.com/1", domain: "c.com"),
            makeNode(url: "https://d.com/1", domain: "d.com"),
        ]
        let urls = nodes.map(\.id)
        let response = ClusterResponse(
            clusters: [DocumentCluster(clusterId: "c1", label: "Test", documentUrls: urls)],
            documents: [:],
            unmatchedUrls: [],
            clusterTimeMs: 10
        )

        let clusters = ConstellationClusterer.clusterFromDIndex(response: response, allNodes: nodes)
        // Top 3 domains; a.com has 2, rest have 1
        #expect(clusters[0].topDomains.first == "a.com")
        #expect(clusters[0].topDomains.count == 3)
    }
}
