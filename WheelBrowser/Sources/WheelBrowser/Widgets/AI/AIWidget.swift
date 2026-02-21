import SwiftUI
import Combine

/// AI-generated widget that displays content based on a JSON configuration
@MainActor
final class AIWidget: Widget, ObservableObject {
    static let typeIdentifier = "aiWidget"
    static let displayName = "AI Widget"
    static let iconName = "sparkles"

    let id: UUID
    @Published var currentSize: WidgetSize = .medium
    @Published var config: AIWidgetConfig
    @Published var content: ExtractedContent = .empty
    @Published var isLoading: Bool = false

    private let fetcher = AIWidgetContentFetcher()
    private var refreshTask: Task<Void, Never>?

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large, .wide]
    }

    init(config: AIWidgetConfig, id: UUID = UUID()) {
        self.id = id
        self.config = config
    }

    @ViewBuilder
    func makeContent() -> some View {
        ZStack {
            AIWidgetContentView(config: config, content: content, size: currentSize)

            if isLoading && content.items.isEmpty {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    func refresh() async {
        // Local widgets don't need a URL, remote widgets do
        guard config.source.type == .local || !config.source.url.isEmpty else {
            print("[AIWidget] refresh skipped - no URL and not local")
            return
        }

        print("[AIWidget] refresh starting for '\(config.name)'")
        isLoading = true
        defer { isLoading = false }

        do {
            content = try await fetcher.fetch(config: config)
            print("[AIWidget] refresh complete - \(content.items.count) items")
        } catch {
            print("[AIWidget] refresh error: \(error)")
            content = ExtractedContent(error: error.localizedDescription)
        }
    }

    /// Start auto-refresh timer if configured
    func startAutoRefresh() {
        guard config.refresh.autoRefresh else {
            print("[AIWidget] startAutoRefresh skipped - autoRefresh disabled")
            return
        }

        print("[AIWidget] startAutoRefresh called for '\(config.name)'")
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                // Use faster refresh for local time-based widgets (clocks, countdowns)
                let refreshInterval: UInt64
                if self.config.source.type == .local,
                   let localConfig = self.config.source.localConfig,
                   localConfig.widgetType == .worldClock || localConfig.widgetType == .countdown {
                    // Refresh every 5 seconds for clocks/countdowns
                    refreshInterval = 5 * 1_000_000_000
                } else if self.config.refresh.intervalMinutes > 0 {
                    refreshInterval = UInt64(self.config.refresh.intervalMinutes) * 60 * 1_000_000_000
                } else {
                    // Default to 30 minutes if not specified
                    refreshInterval = 30 * 60 * 1_000_000_000
                }

                try? await Task.sleep(nanoseconds: refreshInterval)

                if !Task.isCancelled {
                    await self.refresh()
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Configuration Persistence

    func encodeConfiguration() -> [String: Any] {
        do {
            let data = try JSONEncoder().encode(config)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[AIWidget] encodeConfiguration: Failed to convert to dictionary")
                return [:]
            }
            return json
        } catch {
            print("[AIWidget] encodeConfiguration failed: \(error)")
            return [:]
        }
    }

    func decodeConfiguration(_ data: [String: Any]) {
        // Check for empty data (indicates previous encoding failure)
        guard !data.isEmpty else {
            print("[AIWidget] decodeConfiguration: Received empty data, keeping placeholder")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoded = try JSONDecoder().decode(AIWidgetConfig.self, from: jsonData)
            self.config = decoded
            print("[AIWidget] Successfully decoded config: \(decoded.name)")

            // Start refresh after loading config
            Task {
                await refresh()
                startAutoRefresh()
            }
        } catch {
            print("[AIWidget] decodeConfiguration failed: \(error)")
            print("[AIWidget] Data was: \(data)")
        }
    }
}
