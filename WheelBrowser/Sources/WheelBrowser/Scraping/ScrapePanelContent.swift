import SwiftUI

/// Content view for the scrape panel in OmniBar
struct ScrapePanelContent: View {
    @ObservedObject var manager: ScrapeManager

    var body: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if manager.jobs.isEmpty {
                    OmniPanelEmptyState(
                        icon: "network",
                        title: "No scrape jobs",
                        subtitle: "Use Menu > Scrape Page to start"
                    )
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

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .frame(width: 28, height: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayHost)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)

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
        Group {
            if let total = job.total, total > 0 {
                Text("\(job.current)/\(total) pages")
            } else {
                Text("\(job.current) pages")
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
