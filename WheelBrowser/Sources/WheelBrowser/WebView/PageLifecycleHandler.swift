import AppKit
import WebKit

/// Manages page lifecycle events: provisional navigation start, commit,
/// finish, failure, error categorization, and background task tracking.
@MainActor
final class PageLifecycleHandler {
    let tab: Tab

    /// Background tasks (screenshot capture, indexing) that should be cancelled on new navigation.
    private var backgroundTasks: [Task<Void, Never>] = []

    init(tab: Tab) {
        self.tab = tab
    }

    // MARK: - Background Task Management

    /// Cancel all tracked background tasks (e.g., on new navigation).
    func cancelBackgroundTasks() {
        for task in backgroundTasks {
            task.cancel()
        }
        backgroundTasks.removeAll()
    }

    func trackBackgroundTask(_ task: Task<Void, Never>) {
        backgroundTasks.append(task)
    }

    // MARK: - Navigation Lifecycle

    func didStartProvisionalNavigation() {
        cancelBackgroundTasks()
        tab.lastError = nil
        tab.isLoading = true
    }

    func didCommit(navigation: WKNavigation?, webView: WKWebView) {
    }

    func didFinish(navigation: WKNavigation?, webView: WKWebView, indexPage: @escaping (WKWebView, URL, String, UUID?) -> Void) {
        tab.isLoading = false
        tab.title = webView.title ?? "Untitled"
        tab.url = webView.url
        tab.canGoBack = webView.canGoBack
        tab.canGoForward = webView.canGoForward

        // Record to browsing history with current workspace
        if let url = webView.url {
            let title = webView.title ?? "Untitled"
            let workspaceID = WorkspaceManager.shared.currentWorkspaceID
            BrowsingHistory.shared.addEntry(url: url, title: title, workspaceID: workspaceID)

            // Index for semantic search (extract content and embed)
            indexPage(webView, url, title, workspaceID)
        }

        // Inject module content scripts and CSS for matching modules
        if let url = webView.url {
            ModuleInjectionHandler.shared.injectModules(into: webView, for: url)
        }

        // Capture screenshot for tab preview after a short delay
        let captureTab = tab
        let screenshotTask = Task { @MainActor in
            try? await Task.sleep(for: WindowConstants.screenshotDelay)
            guard !Task.isCancelled else { return }
            await TabScreenshotManager.shared.captureScreenshot(for: captureTab)
        }
        trackBackgroundTask(screenshotTask)
    }

    // MARK: - Error Handling

    func handleNavigationError(_ error: Error, isProvisional: Bool) {
        let nsError = error as NSError

        // Ignore cancellation errors (user navigated away, frame cancelled, etc.)
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            tab.isLoading = false
            return
        }

        let categorized = categorizeError(error)
        let phase = isProvisional ? "provisional" : "committed"
        Log.Browser.error("Navigation failed (\(phase)): \(categorized.displayMessage)")

        tab.lastError = categorized
        tab.isLoading = false
    }

    // MARK: - Error Categorization

    private func categorizeError(_ error: Error) -> NavigationError {
        let nsError = error as NSError

        guard nsError.domain == NSURLErrorDomain else {
            return .unknown(message: error.localizedDescription)
        }

        switch nsError.code {
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .hostNotFound
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .ssl(message: error.localizedDescription)
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive:
            return .network(message: error.localizedDescription)
        case NSURLErrorResourceUnavailable,
             NSURLErrorFileDoesNotExist,
             NSURLErrorFileIsDirectory,
             NSURLErrorNoPermissionsToReadFile:
            return .resourceNotFound
        case NSURLErrorBadServerResponse,
             NSURLErrorRedirectToNonExistentLocation,
             NSURLErrorZeroByteResource:
            return .serverError
        default:
            return .unknown(message: error.localizedDescription)
        }
    }
}
