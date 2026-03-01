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

    /// Cached ByteCountFormatter to avoid creating new instances per call
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }

    var formattedSize: String {
        if totalBytes > 0 {
            return "\(Self.byteFormatter.string(fromByteCount: bytesReceived)) / \(Self.byteFormatter.string(fromByteCount: totalBytes))"
        } else if bytesReceived > 0 {
            return Self.byteFormatter.string(fromByteCount: bytesReceived)
        }
        return "Calculating..."
    }

    /// Returns the final file size for completed downloads
    var completedSize: String? {
        // Try to get size from totalBytes first
        if totalBytes > 0 {
            return Self.byteFormatter.string(fromByteCount: totalBytes)
        }

        // Try to get actual file size from destination
        if let url = destinationURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            return Self.byteFormatter.string(fromByteCount: size)
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

    private init() {}

    func startDownload(_ download: WKDownload, filename: String, url: URL, destination: URL, totalBytes: Int64) -> UUID {
        var item = DownloadItem(filename: filename, url: url)
        item.destinationURL = destination
        if totalBytes > 0 {
            item.totalBytes = totalBytes
        }
        downloads.insert(item, at: 0)
        activeDownloads[download] = item.id

        // Show panel when download starts
        withAnimation(AppAnimation.springStandard) {
            showDownloadsPanel = true
        }

        return item.id
    }

    private func index(for id: UUID) -> Int? {
        downloads.firstIndex { $0.id == id }
    }

    private func mutateItem(for download: WKDownload, _ mutation: (inout DownloadItem) -> Void) {
        guard let id = activeDownloads[download],
              let idx = index(for: id) else { return }
        mutation(&downloads[idx])
    }

    func updateProgress(_ download: WKDownload, bytesReceived: Int64, totalBytes: Int64) {
        mutateItem(for: download) {
            $0.bytesReceived = bytesReceived
            $0.totalBytes = totalBytes
        }
    }

    func completeDownload(_ download: WKDownload) {
        mutateItem(for: download) { $0.status = .completed; $0.bytesReceived = $0.totalBytes }
        activeDownloads.removeValue(forKey: download)
    }

    func failDownload(_ download: WKDownload, error: String) {
        mutateItem(for: download) { $0.status = .failed(error) }
        activeDownloads.removeValue(forKey: download)
    }

    func clearCompleted() {
        downloads.removeAll { $0.status != .downloading }
    }

    func revealInFinder(_ item: DownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFile(_ item: DownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openDownloadsFolder() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }

    func togglePanel() {
        withAnimation(AppAnimation.springStandard) {
            showDownloadsPanel.toggle()
        }
    }

    func dismissPanel() {
        withAnimation(AppAnimation.springStandard) {
            showDownloadsPanel = false
        }
    }

    var panelSubtitle: String {
        let activeCount = downloads.filter { $0.status == .downloading }.count
        if activeCount > 0 { return "\(activeCount) downloading" }
        if !downloads.isEmpty { return "\(downloads.count) items" }
        return ""
    }
}
