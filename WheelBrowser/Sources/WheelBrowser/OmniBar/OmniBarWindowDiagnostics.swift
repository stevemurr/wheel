import AppKit
import Foundation

@MainActor
final class OmniBarWindowDiagnostics {
    static let shared = OmniBarWindowDiagnostics()

    private var monitoringTask: Task<Void, Never>?

    private init() {}

    func arm(reason: String) {
        guard monitoringTask == nil else { return }

        let baseline = snapshotWindows()
        Log.OmniBar.debug("Arming window diagnostics for \(reason). Baseline windows: \(baseline.map(\.summary).joined(separator: " | "))")

        monitoringTask = Task { @MainActor [baseline] in
            var knownWindows = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })

            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000)

                let currentWindows = snapshotWindows()
                let currentByID = Dictionary(uniqueKeysWithValues: currentWindows.map { ($0.id, $0) })

                let newWindows = currentWindows.filter { knownWindows[$0.id] == nil }
                for window in newWindows {
                    Log.OmniBar.warning("New window observed during OmniBar focus: \(window.summary)")
                }

                let removedWindows = knownWindows.values.filter { currentByID[$0.id] == nil }
                for window in removedWindows {
                    Log.OmniBar.warning("Window disappeared during OmniBar focus: \(window.summary)")
                }

                knownWindows = currentByID
            }

            monitoringTask = nil
        }
    }

    private func snapshotWindows() -> [WindowSnapshot] {
        NSApp.windows.map(WindowSnapshot.init)
    }
}

private struct WindowSnapshot {
    let id: ObjectIdentifier
    let className: String
    let title: String
    let frame: NSRect
    let isVisible: Bool
    let level: Int

    init(window: NSWindow) {
        id = ObjectIdentifier(window)
        className = String(describing: type(of: window))
        title = window.title.isEmpty ? "<untitled>" : window.title
        frame = window.frame
        isVisible = window.isVisible
        level = Int(window.level.rawValue)
    }

    var summary: String {
        "\(className) title=\(title) visible=\(isVisible) level=\(level) frame=\(NSStringFromRect(frame))"
    }
}
