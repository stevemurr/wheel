import Foundation
import WebKit
import SwiftUI

/// Represents a single download item
struct DownloadItem: Identifiable {
    let id = UUID()
    let filename: String
    let url: URL
    var destinationURL: URL?
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = 0
    var status: DownloadStatus = .downloading
    let startTime: Date = Date()

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if totalBytes > 0 {
            return "\(formatter.string(fromByteCount: bytesReceived)) / \(formatter.string(fromByteCount: totalBytes))"
        } else if bytesReceived > 0 {
            return formatter.string(fromByteCount: bytesReceived)
        }
        return "Calculating..."
    }

    /// Returns the final file size for completed downloads
    var completedSize: String? {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        // Try to get size from totalBytes first
        if totalBytes > 0 {
            return formatter.string(fromByteCount: totalBytes)
        }

        // Try to get actual file size from destination
        if let url = destinationURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            return formatter.string(fromByteCount: size)
        }

        return nil
    }

    enum DownloadStatus: Equatable {
        case downloading
        case completed
        case failed(String)
        case cancelled
    }
}

/// Manages all downloads in the browser
@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [DownloadItem] = []
    @Published var showDownloadsPanel: Bool = false

    private var activeDownloads: [WKDownload: UUID] = [:]

    var hasActiveDownloads: Bool {
        downloads.contains { $0.status == .downloading }
    }

    var recentDownloads: [DownloadItem] {
        downloads.prefix(10).map { $0 }
    }

    private init() {}

    func startDownload(_ download: WKDownload, filename: String, url: URL) -> UUID {
        let item = DownloadItem(filename: filename, url: url)
        downloads.insert(item, at: 0)
        activeDownloads[download] = item.id

        // Show panel when download starts
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showDownloadsPanel = true
        }

        return item.id
    }

    func updateDestination(_ download: WKDownload, destination: URL) {
        guard let id = activeDownloads[download],
              let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].destinationURL = destination
    }

    func updateProgress(_ download: WKDownload, bytesReceived: Int64, totalBytes: Int64) {
        guard let id = activeDownloads[download],
              let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].bytesReceived = bytesReceived
        downloads[index].totalBytes = totalBytes
    }

    func completeDownload(_ download: WKDownload) {
        guard let id = activeDownloads[download],
              let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].status = .completed
        downloads[index].bytesReceived = downloads[index].totalBytes
        activeDownloads.removeValue(forKey: download)
    }

    func failDownload(_ download: WKDownload, error: String) {
        guard let id = activeDownloads[download],
              let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].status = .failed(error)
        activeDownloads.removeValue(forKey: download)
    }

    func cancelDownload(_ download: WKDownload) {
        guard let id = activeDownloads[download],
              let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].status = .cancelled
        activeDownloads.removeValue(forKey: download)
    }

    func clearCompleted() {
        downloads.removeAll { item in
            item.status == .completed || item.status == .cancelled ||
            (item.status != .downloading && item.status != .completed)
        }
    }

    func revealInFinder(_ item: DownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFile(_ item: DownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.open(url)
    }

    func togglePanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showDownloadsPanel.toggle()
        }
    }

    func dismissPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showDownloadsPanel = false
        }
    }
}

// MARK: - Downloads Panel Content (used inside OmniPanel)

struct DownloadsPanelContent: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if manager.downloads.isEmpty {
                    OmniPanelEmptyState(
                        icon: "arrow.down.to.line",
                        title: "No downloads yet",
                        subtitle: "Downloads will appear here"
                    )
                    .padding(.top, 30)
                } else {
                    ForEach(manager.downloads) { item in
                        DownloadItemRow(item: item, manager: manager)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(minHeight: 80)
    }

    var subtitle: String {
        let activeCount = manager.downloads.filter { $0.status == .downloading }.count
        if activeCount > 0 {
            return "\(activeCount) active"
        } else if !manager.downloads.isEmpty {
            return "\(manager.downloads.count) items"
        }
        return ""
    }
}

struct DownloadItemRow: View {
    let item: DownloadItem
    let manager: DownloadManager
    @State private var isHovering = false

    private var fileExtension: String {
        (item.filename as NSString).pathExtension.lowercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            // File icon (28x28 to match other panels)
            fileIcon
                .frame(width: 28, height: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                statusSubtitle
            }

            Spacer()

            // Right side: status badge or action buttons
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
        .modifier(PointerCursorModifier())
    }

    @ViewBuilder
    private var fileIcon: some View {
        let (iconName, iconColor) = iconForExtension(fileExtension)

        Image(systemName: iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor)
            )
    }

    private func iconForExtension(_ ext: String) -> (String, Color) {
        switch ext {
        case "pdf":
            return ("doc.fill", .red)
        case "zip", "rar", "7z", "tar", "gz":
            return ("archivebox.fill", .brown)
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return ("photo.fill", .blue)
        case "mp4", "mov", "avi", "mkv", "webm":
            return ("film.fill", .purple)
        case "mp3", "wav", "flac", "aac", "m4a":
            return ("music.note", .pink)
        case "doc", "docx":
            return ("doc.text.fill", .blue)
        case "xls", "xlsx":
            return ("tablecells.fill", .green)
        case "dmg", "pkg":
            return ("shippingbox.fill", .gray)
        default:
            return ("doc.fill", .secondary)
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch item.status {
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: item.progress)
                    .frame(width: 80)
                Text(item.formattedSize)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .completed:
            if let size = item.completedSize {
                Text(size)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Completed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
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

    @ViewBuilder
    private var rightIndicator: some View {
        switch item.status {
        case .downloading:
            // Progress percentage badge
            Text("\(Int(item.progress * 100))%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )

        case .completed:
            // Action buttons in compact style
            HStack(spacing: 4) {
                Button(action: { manager.openFile(item) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help("Open")

                Button(action: { manager.revealInFinder(item) }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }

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

// MARK: - Pointer Cursor Modifier

/// A view modifier that changes the cursor to a pointing hand when hovering
struct PointerCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(
            PointerCursorView()
        )
    }
}

/// NSViewRepresentable that sets up a tracking area for cursor changes
struct PointerCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class TrackingView: NSView {
        var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let existingArea = trackingArea {
                removeTrackingArea(existingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
        }
    }
}
