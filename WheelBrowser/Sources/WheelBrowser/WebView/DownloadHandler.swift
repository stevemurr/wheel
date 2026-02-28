import Foundation
import WebKit

/// Manages file download lifecycle: destination selection, progress tracking,
/// completion, and failure handling.
///
/// Conforms to `WKDownloadDelegate` directly so the Coordinator can set
/// `download.delegate = downloadHandler` instead of `self`.
class DownloadHandler: NSObject, WKDownloadDelegate {

    /// KVO observations tracking download progress.
    private var progressObservations: [WKDownload: NSKeyValueObservation] = [:]

    // MARK: - WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        // Get Downloads folder
        guard let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            completionHandler(nil)
            return
        }

        // Create unique filename if needed
        var destinationURL = downloadsURL.appendingPathComponent(suggestedFilename)
        destinationURL = Self.uniqueFileURL(basePath: destinationURL)

        // Register with DownloadManager and set up progress tracking
        let sourceURL = response.url ?? URL(string: "about:blank")!
        let expectedLength = response.expectedContentLength

        Task { @MainActor in
            _ = DownloadManager.shared.startDownload(download, filename: suggestedFilename, url: sourceURL)
            DownloadManager.shared.updateDestination(download, destination: destinationURL)

            // Set initial total bytes if known
            if expectedLength > 0 {
                DownloadManager.shared.updateProgress(download, bytesReceived: 0, totalBytes: expectedLength)
            }
        }

        // Set up KVO observation for download progress
        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            guard self != nil else { return }
            let totalBytes = progress.totalUnitCount
            let completedBytes = progress.completedUnitCount
            Task { @MainActor in
                DownloadManager.shared.updateProgress(download, bytesReceived: completedBytes, totalBytes: totalBytes)
            }
        }
        progressObservations[download] = observation

        completionHandler(destinationURL)
    }

    func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Use default handling for authentication challenges
        completionHandler(.performDefaultHandling, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        progressObservations.removeValue(forKey: download)

        Task { @MainActor in
            DownloadManager.shared.completeDownload(download)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        progressObservations.removeValue(forKey: download)

        Task { @MainActor in
            DownloadManager.shared.failDownload(download, error: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Generate a unique file URL by appending ` (N)` if the path already exists.
    static func uniqueFileURL(basePath: URL) -> URL {
        var destinationURL = basePath
        var counter = 1
        let fileExtension = basePath.pathExtension
        let fileNameWithoutExtension = basePath.deletingPathExtension().lastPathComponent
        let directory = basePath.deletingLastPathComponent()

        while FileManager.default.fileExists(atPath: destinationURL.path) {
            let newFileName: String
            if fileExtension.isEmpty {
                newFileName = "\(fileNameWithoutExtension) (\(counter))"
            } else {
                newFileName = "\(fileNameWithoutExtension) (\(counter)).\(fileExtension)"
            }
            destinationURL = directory.appendingPathComponent(newFileName)
            counter += 1
        }

        return destinationURL
    }
}
