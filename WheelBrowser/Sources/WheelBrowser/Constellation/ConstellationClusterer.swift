import Foundation
import SwiftUI

/// Clusters constellation nodes by domain or by DIndex semantic categories
enum ConstellationClusterer {

    /// Cluster the given nodes by domain (fast, no network).
    static func clusterByDomain(nodes: [ConstellationNode]) -> [ConstellationCluster] {
        var domainGroups: [String: [ConstellationNode]] = [:]

        for node in nodes {
            let domain = node.domain.isEmpty ? "Other" : node.domain
            domainGroups[domain, default: []].append(node)
        }

        return domainGroups
            .sorted(by: { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key })
            .enumerated()
            .map { idx, pair in
                let colorIdx = idx % ConstellationCluster.clusterColors.count
                return ConstellationCluster(
                    id: pair.key,
                    nodeIds: pair.value.map(\.id),
                    label: pair.key,
                    color: ConstellationCluster.clusterColors[colorIdx],
                    topDomains: [pair.key]
                )
            }
    }

    /// Build clusters from a DIndex cluster response.
    /// Nodes not covered by the response fall back to domain-based grouping.
    static func clusterFromDIndex(
        response: ClusterResponse,
        allNodes: [ConstellationNode]
    ) -> [ConstellationCluster] {
        let nodeById = Dictionary(allNodes.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        var assignedIds = Set<String>()
        var clusters: [ConstellationCluster] = []

        for (idx, dc) in response.clusters.enumerated() {
            let memberIds = dc.documentUrls.filter { nodeById[$0] != nil }
            guard !memberIds.isEmpty else { continue }
            assignedIds.formUnion(memberIds)

            // Compute top 3 domains by frequency
            let domains = memberIds.compactMap { nodeById[$0]?.domain }
            let topDomains = topN(domains, n: 3)

            let colorIdx = idx % ConstellationCluster.clusterColors.count
            clusters.append(ConstellationCluster(
                id: dc.clusterId,
                nodeIds: memberIds,
                label: dc.label,
                color: ConstellationCluster.clusterColors[colorIdx],
                topDomains: topDomains
            ))
        }

        // Group unmatched nodes by domain as fallback
        let unmatchedNodes = allNodes.filter { !assignedIds.contains($0.id) }
        if !unmatchedNodes.isEmpty {
            var domainGroups: [String: [ConstellationNode]] = [:]
            for node in unmatchedNodes {
                let domain = node.domain.isEmpty ? "Other" : node.domain
                domainGroups[domain, default: []].append(node)
            }
            let offset = clusters.count
            let fallback = domainGroups
                .sorted(by: { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key })
                .enumerated()
                .map { idx, pair -> ConstellationCluster in
                    let colorIdx = (offset + idx) % ConstellationCluster.clusterColors.count
                    return ConstellationCluster(
                        id: "fallback_\(pair.key)",
                        nodeIds: pair.value.map(\.id),
                        label: pair.key,
                        color: ConstellationCluster.clusterColors[colorIdx],
                        topDomains: [pair.key]
                    )
                }
            clusters.append(contentsOf: fallback)
        }

        return clusters
    }

    /// Return the top N most frequent strings, ordered by descending frequency.
    private static func topN(_ items: [String], n: Int) -> [String] {
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(n)
            .map(\.key)
    }
}
