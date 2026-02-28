import Foundation
import SwiftUI
import DIndexClient

/// Per-URL progress tracking
struct UrlProgress: Identifiable {
    let url: String
    let depth: UInt8
    var status: UrlProgressStatus
    var title: String?
    var chunksCreated: Int = 0
    var durationMs: UInt64?
    var error: String?

    var id: String { url }

    /// Display string for the URL (path component after host)
    var displayPath: String {
        guard let urlObj = URL(string: url) else { return url }
        let path = urlObj.path
        return path.isEmpty ? "/" : path
    }
}

/// Status of an individual URL being scraped
enum UrlProgressStatus {
    case queued
    case fetching
    case indexed
    case failed
    case skipped

    var iconName: String {
        switch self {
        case .queued: return "clock"
        case .fetching: return "arrow.down.circle"
        case .indexed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .queued: return .secondary
        case .fetching: return .cyan
        case .indexed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }
}

/// Represents a scraping job with its current state
struct ScrapeJob: Identifiable {
    let id: String
    let url: URL
    let startTime: Date
    var status: ScrapeJobStatus
    var current: UInt64 = 0
    var total: UInt64?
    var rate: Double?
    var etaSeconds: UInt64?
    var chunksIndexed: Int = 0

    /// Per-URL progress tracking
    var urlProgress: [UrlProgress] = []

    /// URL currently being fetched
    var currentUrl: String?

    /// Progress as a percentage (0.0 to 1.0)
    var progress: Double {
        guard let total = total, total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    /// Display string for the URL (host only)
    var displayHost: String {
        url.host ?? url.absoluteString
    }

    /// Count of successfully indexed URLs
    var indexedCount: Int {
        urlProgress.filter { $0.status == .indexed }.count
    }

    /// Count of failed URLs
    var failedCount: Int {
        urlProgress.filter { $0.status == .failed }.count
    }
}

/// Status of a scrape job
enum ScrapeJobStatus: Equatable {
    case starting
    case scraping
    case indexing
    case completed(pagesIndexed: Int)
    case failed(error: String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .starting, .scraping, .indexing:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .starting:
            return "Starting..."
        case .scraping:
            return "Scraping..."
        case .indexing:
            return "Indexing..."
        case .completed(let pages):
            return "\(pages) pages indexed"
        case .failed(let error):
            return "Failed: \(error)"
        case .cancelled:
            return "Cancelled"
        }
    }
}

/// Manages web scraping jobs and their progress
@MainActor
class ScrapeManager: ObservableObject {
    static let shared = ScrapeManager()

    @Published var jobs: [ScrapeJob] = []
    @Published var showScrapePanel: Bool = false

    /// Active SSE subscription tasks per job ID
    private var subscriptionTasks: [String: Task<Void, Never>] = [:]

    /// Whether there are any active jobs
    var hasActiveJobs: Bool {
        jobs.contains { $0.status.isActive }
    }

    /// Number of active jobs
    var activeJobCount: Int {
        jobs.filter { $0.status.isActive }.count
    }

    /// Subtitle text for the panel
    var panelSubtitle: String {
        let active = activeJobCount
        if active > 0 {
            return "\(active) scraping"
        } else if !jobs.isEmpty {
            return "\(jobs.count) jobs"
        }
        return ""
    }

    private init() {}

    /// Start a new scrape job
    ///
    /// - Parameters:
    ///   - url: The URL to start scraping from
    ///   - depth: Maximum crawl depth (0 = current page only)
    ///   - stayOnDomain: Whether to stay on the same domain
    ///   - maxPages: Maximum number of pages to scrape
    func startScrape(
        url: URL,
        depth: UInt8,
        stayOnDomain: Bool,
        maxPages: Int
    ) async throws {
        guard let service = SemanticSearchManagerV2.shared.dIndexService else {
            throw ScrapeError.serviceUnavailable
        }

        Log.Scrape.info("Starting scrape: url=\(url.absoluteString), depth=\(depth), stayOnDomain=\(stayOnDomain), maxPages=\(maxPages)")

        let jobId = try await service.startScrape(
            url: url,
            depth: depth,
            stayOnDomain: stayOnDomain,
            maxPages: maxPages
        )

        let job = ScrapeJob(
            id: jobId,
            url: url,
            startTime: Date(),
            status: .starting
        )

        jobs.insert(job, at: 0)

        // Show panel when job starts
        withAnimation(AppAnimation.springStandard) {
            showScrapePanel = true
        }

        // Subscribe to SSE events for this job
        subscribeToJobEvents(jobId: jobId, service: service)

        Log.Scrape.info("Scrape job started: \(jobId)")
    }

    /// Cancel a running job
    func cancelJob(_ jobId: String) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }

        // Cancel SSE subscription
        subscriptionTasks[jobId]?.cancel()
        subscriptionTasks.removeValue(forKey: jobId)

        do {
            guard let service = SemanticSearchManagerV2.shared.dIndexService else {
                throw ScrapeError.serviceUnavailable
            }
            try await service.cancelScrape(jobId: jobId)
            jobs[index].status = .cancelled
            Log.Scrape.info("Scrape job cancelled: \(jobId)")
        } catch {
            Log.Scrape.error("Failed to cancel scrape job", error: error)
        }
    }

    /// Clear all completed/failed/cancelled jobs
    func clearCompleted() {
        let completedIds = jobs.filter { !$0.status.isActive }.map { $0.id }
        for id in completedIds {
            subscriptionTasks[id]?.cancel()
            subscriptionTasks.removeValue(forKey: id)
        }
        jobs.removeAll { !$0.status.isActive }
    }

    /// Toggle panel visibility
    func togglePanel() {
        withAnimation(AppAnimation.springStandard) {
            showScrapePanel.toggle()
        }
    }

    /// Dismiss the panel
    func dismissPanel() {
        withAnimation(AppAnimation.springStandard) {
            showScrapePanel = false
        }
    }

    // MARK: - SSE Event Handling

    private func subscribeToJobEvents(jobId: String, service: DIndexService) {
        let stream = service.subscribeScrapeEvents(jobId: jobId)

        let task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self = self else { break }
                    if Task.isCancelled { break }

                    await MainActor.run {
                        self.handleScrapeEvent(event, jobId: jobId)
                    }
                }
            } catch {
                Log.Scrape.warning("SSE stream error for job \(jobId): \(error.localizedDescription)")
            }

            // Clean up subscription when done
            await MainActor.run { [weak self] in
                self?.subscriptionTasks.removeValue(forKey: jobId)
            }
        }

        subscriptionTasks[jobId] = task
    }

    private func handleScrapeEvent(_ event: ScrapeEvent, jobId: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }

        switch event {
        case .jobStarted(_, let seedUrls, _, _):
            jobs[index].status = .scraping
            jobs[index].total = UInt64(seedUrls.count)
            Log.Scrape.debug("Job \(jobId) started with \(seedUrls.count) seed URLs")

        case .urlQueued(_, let url, let depth, _):
            // Add URL to progress tracking if not already present
            if !jobs[index].urlProgress.contains(where: { $0.url == url }) {
                jobs[index].urlProgress.append(UrlProgress(
                    url: url,
                    depth: depth,
                    status: .queued
                ))
            }

        case .urlFetching(_, let url):
            jobs[index].currentUrl = url
            if let urlIndex = jobs[index].urlProgress.firstIndex(where: { $0.url == url }) {
                jobs[index].urlProgress[urlIndex].status = .fetching
            }

        case .urlIndexed(_, let url, let title, _, let chunksCreated, let durationMs, _):
            jobs[index].currentUrl = nil
            if let urlIndex = jobs[index].urlProgress.firstIndex(where: { $0.url == url }) {
                jobs[index].urlProgress[urlIndex].status = .indexed
                jobs[index].urlProgress[urlIndex].title = title
                jobs[index].urlProgress[urlIndex].chunksCreated = chunksCreated
                jobs[index].urlProgress[urlIndex].durationMs = durationMs
            }

        case .urlFailed(_, let url, let error, let durationMs):
            jobs[index].currentUrl = nil
            if let urlIndex = jobs[index].urlProgress.firstIndex(where: { $0.url == url }) {
                jobs[index].urlProgress[urlIndex].status = .failed
                jobs[index].urlProgress[urlIndex].error = error
                jobs[index].urlProgress[urlIndex].durationMs = durationMs
            }

        case .urlSkipped(_, let url, let reason):
            if let urlIndex = jobs[index].urlProgress.firstIndex(where: { $0.url == url }) {
                jobs[index].urlProgress[urlIndex].status = .skipped
                jobs[index].urlProgress[urlIndex].error = reason
            }

        case .progress(_, let urlsProcessed, _, _, _, let urlsQueued, let chunksIndexed, _, let rate, let etaSeconds):
            jobs[index].current = urlsProcessed
            jobs[index].total = UInt64(urlsQueued) + urlsProcessed
            jobs[index].chunksIndexed = chunksIndexed
            jobs[index].rate = rate
            jobs[index].etaSeconds = etaSeconds
            jobs[index].status = .scraping

        case .jobCompleted(_, let status, let stats, let error):
            jobs[index].currentUrl = nil
            if status == "completed" {
                let pagesIndexed = stats?.documentsProcessed ?? jobs[index].indexedCount
                jobs[index].status = .completed(pagesIndexed: pagesIndexed)
                if let stats = stats {
                    jobs[index].chunksIndexed = stats.chunksIndexed
                }
                // Refresh semantic search stats to show updated document count
                Task {
                    await SemanticSearchManagerV2.shared.refreshStats()
                }
            } else if status == "cancelled" {
                jobs[index].status = .cancelled
            } else {
                jobs[index].status = .failed(error: error ?? "Unknown error")
            }
            Log.Scrape.info("Job \(jobId) completed with status: \(status)")

        case .lagged(let missed):
            Log.Scrape.warning("Job \(jobId) SSE lagged, missed \(missed) events")
        }
    }
}

// MARK: - Errors

enum ScrapeError: LocalizedError {
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Semantic search service is not available"
        }
    }
}
