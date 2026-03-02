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

            // Generate readable label from page titles
            let titles = memberIds.compactMap { url -> String? in
                response.documents[url]?.title ?? nodeById[url]?.title
            }.filter { !$0.isEmpty }
            let label = generateLabel(titles: titles, topDomains: topDomains)
                ?? topDomains.first
                ?? dc.label

            let colorIdx = idx % ConstellationCluster.clusterColors.count
            clusters.append(ConstellationCluster(
                id: dc.clusterId,
                nodeIds: memberIds,
                label: label,
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

    // MARK: - Label generation

    private static let stopWords: Set<String> = [
        // Common English
        "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
        "her", "was", "one", "our", "out", "has", "have", "been", "from", "its",
        "that", "this", "with", "will", "your", "about", "into", "them", "then",
        "than", "they", "what", "when", "where", "which", "who", "how", "each",
        "she", "his", "him", "does", "did", "get", "got", "just", "more", "most",
        "some", "very", "also", "here", "there", "would", "could", "should",
        // Web noise
        "http", "https", "www", "html", "htm", "php", "asp", "page", "home",
        "index", "site", "web", "online", "untitled", "null", "undefined",
        "com", "org", "net", "dev",
    ]

    /// Generate a readable label from page titles in a cluster.
    /// Returns `nil` if no meaningful words remain after filtering.
    private static func generateLabel(titles: [String], topDomains: [String]) -> String? {
        let domainFragments = Set(topDomains.flatMap { domain in
            domain.lowercased()
                .components(separatedBy: ".")
                .filter { $0.count > 2 }
        })

        // Count word frequency, deduplicated per-title
        var wordCounts: [String: Int] = [:]
        for title in titles {
            let words = title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { word in
                    word.count > 2
                        && !stopWords.contains(word)
                        && !domainFragments.contains(word)
                }
            // Deduplicate within this title
            for word in Set(words) {
                wordCounts[word, default: 0] += 1
            }
        }

        let topWords = wordCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map { $0.key.prefix(1).uppercased() + $0.key.dropFirst() }

        guard !topWords.isEmpty else { return nil }

        // Use top 2 if third word only appeared once, otherwise top 3
        let count = topWords.count >= 3 && wordCounts[topWords[2].lowercased()] ?? 0 <= 1 ? 2 : topWords.count
        return topWords.prefix(count).joined(separator: " & ")
    }
}
