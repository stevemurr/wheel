import Foundation
import SwiftUI
import DIndexClient

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

    /// Progress as a percentage (0.0 to 1.0)
    var progress: Double {
        guard let total = total, total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    /// Display string for the URL (host only)
    var displayHost: String {
        url.host ?? url.absoluteString
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

    /// Polling interval for active jobs
    private let pollInterval: TimeInterval = 2.0
    private var pollTask: Task<Void, Never>?

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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showScrapePanel = true
        }

        // Start polling if not already running
        startPollingIfNeeded()

        Log.Scrape.info("Scrape job started: \(jobId)")
    }

    /// Cancel a running job
    func cancelJob(_ jobId: String) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }

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
        jobs.removeAll { !$0.status.isActive }
    }

    /// Toggle panel visibility
    func togglePanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showScrapePanel.toggle()
        }
    }

    /// Dismiss the panel
    func dismissPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showScrapePanel = false
        }
    }

    // MARK: - Polling

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                // Check if there are active jobs
                let hasActive = await MainActor.run { self.hasActiveJobs }
                guard hasActive else {
                    await MainActor.run { self.stopPolling() }
                    break
                }

                // Poll all active jobs
                await self.pollActiveJobs()

                // Wait before next poll
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollActiveJobs() async {
        guard let service = SemanticSearchManagerV2.shared.dIndexService else { return }

        // Get list of active job IDs
        let activeJobIds = jobs.filter { $0.status.isActive }.map { $0.id }

        for jobId in activeJobIds {
            do {
                let progress = try await service.getScrapeProgress(jobId: jobId)
                await updateJobProgress(jobId: jobId, progress: progress)
            } catch {
                Log.Scrape.warning("Failed to poll job \(jobId): \(error.localizedDescription)")
            }
        }
    }

    private func updateJobProgress(jobId: String, progress: JobProgress) async {
        await MainActor.run {
            guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }

            jobs[index].current = progress.current
            jobs[index].total = progress.total
            jobs[index].rate = progress.rate
            jobs[index].etaSeconds = progress.etaSeconds

            // Update status based on stage
            if progress.isCompleted {
                jobs[index].status = .completed(pagesIndexed: Int(progress.current))
            } else if progress.isFailed {
                jobs[index].status = .failed(error: progress.errorMessage ?? "Unknown error")
            } else if progress.stage.contains("index") {
                jobs[index].status = .indexing
            } else {
                jobs[index].status = .scraping
            }
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
