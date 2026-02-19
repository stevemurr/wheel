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
        guard !config.source.url.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            content = try await fetcher.fetch(config: config)
        } catch {
            content = ExtractedContent(error: error.localizedDescription)
        }
    }

    /// Start auto-refresh timer if configured
    func startAutoRefresh() {
        guard config.refresh.autoRefresh, config.refresh.intervalMinutes > 0 else { return }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                try? await Task.sleep(nanoseconds: UInt64(config.refresh.intervalMinutes) * 60 * 1_000_000_000)

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
        guard let data = try? JSONEncoder().encode(config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    func decodeConfiguration(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let decoded = try? JSONDecoder().decode(AIWidgetConfig.self, from: jsonData) else {
            return
        }
        self.config = decoded

        // Start refresh after loading config
        Task {
            await refresh()
            startAutoRefresh()
        }
    }
}
