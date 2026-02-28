import SwiftUI

/// Content view for the scrape panel in OmniBar
struct ScrapePanelContent: View {
    @ObservedObject var manager: ScrapeManager

    var body: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if manager.jobs.isEmpty {
                    VStack(spacing: 16) {
                        OmniPanelEmptyState(
                            icon: "network",
                            title: "No scrape jobs",
                            subtitle: "Scrape and index pages for semantic search"
                        )

                        Button(action: {
                            NotificationCenter.default.post(name: .scrapePage, object: nil)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Start New Scrape")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.cyan)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 30)
                } else {
                    ForEach(manager.jobs) { job in
                        ScrapeJobRow(job: job, manager: manager)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(minHeight: 80)
    }
}

/// Row displaying a single scrape job
struct ScrapeJobRow: View {
    let job: ScrapeJob
    let manager: ScrapeManager
    @State private var isHovering = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main job row
            HStack(spacing: 12) {
                // Expand/collapse chevron for active jobs with URLs
                if job.status.isActive && !job.urlProgress.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Status icon for non-active jobs
                    statusIcon
                        .frame(width: 28, height: 28)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(job.displayHost)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        // Show current URL being fetched
                        if job.status.isActive, let currentUrl = job.currentUrl,
                           let urlObj = URL(string: currentUrl) {
                            Text(urlObj.path.isEmpty ? "/" : urlObj.path)
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    statusSubtitle
                }

                Spacer()

                // Right side: progress or action buttons
                rightIndicator
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
            }

            // Expanded URL list
            if isExpanded && !job.urlProgress.isEmpty {
                VStack(spacing: 2) {
                    ForEach(job.urlProgress.suffix(20)) { urlProgress in
                        UrlProgressRow(urlProgress: urlProgress)
                    }

                    if job.urlProgress.count > 20 {
                        Text("+ \(job.urlProgress.count - 20) more URLs")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.leading, 40)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let (iconName, iconColor, shouldSpin) = iconForStatus(job.status)

        ZStack {
            if shouldSpin {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(iconColor)
                    )
            }
        }
    }

    private func iconForStatus(_ status: ScrapeJobStatus) -> (String, Color, Bool) {
        switch status {
        case .starting:
            return ("arrow.down.circle", .cyan, true)
        case .scraping:
            return ("network", .cyan, true)
        case .indexing:
            return ("doc.text.magnifyingglass", .cyan, true)
        case .completed:
            return ("checkmark", .green, false)
        case .failed:
            return ("xmark", .red, false)
        case .cancelled:
            return ("slash.circle", .secondary, false)
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch job.status {
        case .starting:
            Text("Starting...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

        case .scraping, .indexing:
            HStack(spacing: 6) {
                ProgressView(value: job.progress)
                    .frame(width: 80)
                    .tint(.cyan)
                progressText
            }

        case .completed(let pages):
            Text("\(pages) pages indexed")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

        case .failed(let error):
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.8))
                .lineLimit(1)

        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var progressText: some View {
        HStack(spacing: 4) {
            // Pages processed
            if let total = job.total, total > 0 {
                Text("\(job.current)/\(total)")
            } else {
                Text("\(job.current)")
            }

            // Show indexed/failed counts if available
            if job.indexedCount > 0 || job.failedCount > 0 {
                Text("•")
                    .foregroundColor(.secondary.opacity(0.5))

                if job.indexedCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("\(job.indexedCount)")
                    }
                }

                if job.failedCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.red)
                        Text("\(job.failedCount)")
                    }
                }
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var rightIndicator: some View {
        switch job.status {
        case .starting, .scraping, .indexing:
            // Cancel button for active jobs
            Button(action: {
                Task {
                    await manager.cancelJob(job.id)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
            .help("Cancel")

        case .completed:
            // Done badge
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9))
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.1))
            )

        case .failed:
            // Error badge
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text("Failed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.1))
            )

        case .cancelled:
            // Cancelled badge
            Text("Cancelled")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
        }
    }
}

/// Row displaying progress for a single URL
struct UrlProgressRow: View {
    let urlProgress: UrlProgress

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: urlProgress.status.iconName)
                .font(.system(size: 10))
                .foregroundColor(urlProgress.status.iconColor)
                .frame(width: 14)

            // URL path
            Text(urlProgress.displayPath)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Additional info based on status
            Group {
                switch urlProgress.status {
                case .indexed:
                    if urlProgress.chunksCreated > 0 {
                        Text("\(urlProgress.chunksCreated) chunks")
                            .foregroundColor(.green.opacity(0.8))
                    }

                case .failed:
                    if let error = urlProgress.error {
                        Text(error)
                            .foregroundColor(.red.opacity(0.8))
                            .lineLimit(1)
                    }

                case .skipped:
                    if let reason = urlProgress.error {
                        Text(reason)
                            .foregroundColor(.orange.opacity(0.8))
                            .lineLimit(1)
                    }

                case .fetching:
                    ProgressView()
                        .scaleEffect(0.4)

                case .queued:
                    Text("queued")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 10))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}
