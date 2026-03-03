import Foundation

/// A single widget instance holding its pipeline spec, cached data, and refresh state.
@Observable
@MainActor
final class WidgetInstance: Identifiable {
    let id: UUID
    var spec: WidgetPipelineSpec
    var lastData: RenderInput?
    var lastFetched: Date?
    var isLoading: Bool = false
    var error: String?

    private let executor: PipelineExecutor

    init(spec: WidgetPipelineSpec, executor: PipelineExecutor) {
        self.id = spec.widgetId
        self.spec = spec
        self.executor = executor
    }

    /// Whether this widget is stale and should be refreshed.
    var isStale: Bool {
        guard let lastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) >= Double(spec.refreshIntervalSeconds)
    }

    /// Re-execute the pipeline and update cached data.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let validated = ValidatedSpec(trusted: spec)
            let result = try await executor.execute(validated)
            lastData = result
            lastFetched = Date()
        } catch {
            self.error = error.localizedDescription
            Log.Widgets.error("Widget '\(spec.title)' refresh failed", error: error)
        }

        isLoading = false
    }
}

// MARK: - Persistence Model

/// Codable representation for persisting widget specs to disk.
struct PersistedWidget: Codable {
    let spec: WidgetPipelineSpec
    let position: Int
}
