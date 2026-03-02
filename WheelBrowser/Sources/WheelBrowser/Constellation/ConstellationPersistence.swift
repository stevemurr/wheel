import Foundation
import Combine

/// Saves and loads node positions for the Constellation canvas per workspace
@MainActor
final class ConstellationPersistence {
    static let shared = ConstellationPersistence()

    private var positions: [String: CGPoint] = [:]
    private var workspaceId: UUID?
    private var saveCancellable: AnyCancellable?
    private let saveSubject = PassthroughSubject<Void, Never>()
    /// URLs of nodes currently displayed — used for recency-based pruning
    private var currentNodeURLs: Set<String> = []

    private init() {
        saveCancellable = saveSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.save()
            }
    }

    private var fileURL: URL? {
        guard let workspaceId else { return nil }
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = appSupport.appendingPathComponent("WheelBrowser")
        return dir.appendingPathComponent("constellation_\(workspaceId.uuidString).json")
    }

    func setWorkspace(_ id: UUID?) {
        // Save current workspace positions before switching
        if workspaceId != nil {
            save()
        }
        self.workspaceId = id
        load()
    }

    func loadPosition(for url: URL) -> CGPoint? {
        positions[url.absoluteString]
    }

    func savePosition(url: URL, position: CGPoint) {
        positions[url.absoluteString] = position
        scheduleSave()
    }

    private func scheduleSave() {
        saveSubject.send()
    }

    /// Save all node positions. Only call in history mode (search positions are ephemeral).
    /// Also records which URLs are currently active for recency-based pruning.
    func saveAll(nodePositions: [String: CGPoint], nodes: [ConstellationNode]) {
        let activeURLs = Set(nodes.map { $0.url.absoluteString })
        currentNodeURLs = activeURLs
        for node in nodes {
            if let pos = nodePositions[node.id] {
                positions[node.url.absoluteString] = pos
            }
        }
        save()
    }

    // MARK: - Private

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            positions.removeAll()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(PersistedConstellationData.self, from: data)
            positions = [:]
            for (key, point) in decoded.positions {
                positions[key] = CGPoint(x: point.x, y: point.y)
            }
        } catch {
            #if DEBUG
            print("[ConstellationPersistence] load failed: \(error)")
            #endif
            positions.removeAll()
        }
    }

    private static let maxPersistedPositions = 500

    private func save() {
        guard let fileURL else { return }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Prune to max count — prefer keeping positions for currently-active nodes
        if positions.count > Self.maxPersistedPositions {
            let activeKeys = positions.keys.filter { currentNodeURLs.contains($0) }
            let staleKeys = positions.keys.filter { !currentNodeURLs.contains($0) }
            let excess = positions.count - Self.maxPersistedPositions
            // Remove stale entries first, then active entries if still over limit
            let toRemove = Array(staleKeys.prefix(excess))
            for key in toRemove {
                positions.removeValue(forKey: key)
            }
            if positions.count > Self.maxPersistedPositions {
                let stillExcess = positions.count - Self.maxPersistedPositions
                for key in activeKeys.suffix(stillExcess) {
                    positions.removeValue(forKey: key)
                }
            }
        }

        var encodable: [String: PersistedPoint] = [:]
        for (key, point) in positions {
            encodable[key] = PersistedPoint(x: point.x, y: point.y)
        }

        do {
            let encoded = try JSONEncoder().encode(PersistedConstellationData(positions: encodable))
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[ConstellationPersistence] save failed: \(error)")
            #endif
        }
    }
}

// MARK: - Codable models

private struct PersistedPoint: Codable {
    let x: Double
    let y: Double
}

private struct PersistedConstellationData: Codable {
    let positions: [String: PersistedPoint]
}
