import SwiftUI
import WebKit
import AuthenticationServices

struct WebViewRepresentable: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        tab.webView.uiDelegate = context.coordinator
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView updates handled by Tab
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let tab: Tab
        private var currentDownload: WKDownload?
        private var downloadFilename: String = ""
        private var progressObservations: [WKDownload: NSKeyValueObservation] = [:]

        init(tab: Tab) {
            self.tab = tab
        }

        // MARK: - Download MIME Types

        private let downloadableMimeTypes: Set<String> = [
            "application/octet-stream",
            "application/zip",
            "application/x-zip-compressed",
            "application/x-rar-compressed",
            "application/gzip",
            "application/x-gzip",
            "application/x-tar",
            "application/x-7z-compressed",
            "application/pdf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/x-apple-diskimage",
            "application/x-dmg",
            "application/x-bzip2",
            "application/x-xz",
            "application/java-archive",
            "application/x-shockwave-flash",
            "application/x-msdownload",
            "application/x-msdos-program",
            "video/mp4",
            "video/quicktime",
            "video/x-msvideo",
            "video/x-matroska",
            "video/webm",
            "audio/mpeg",
            "audio/mp4",
            "audio/x-wav",
            "audio/flac",
            "audio/ogg"
        ]

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.isLoading = true
                // Invalidate screenshot when navigation starts (keeps old one until new capture)
                TabScreenshotManager.shared.invalidateScreenshot(for: self.tab.id)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // Apply dark mode as early as possible when navigation commits
            // This runs before didFinish and helps prevent flash of light content
            DispatchQueue.main.async {
                self.applyDarkModeIfNeeded(to: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
                self.tab.title = webView.title ?? "Untitled"
                self.tab.url = webView.url
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward

                // Re-apply dark mode state after navigation
                // This ensures dark mode is applied even if settings changed after tab creation
                self.applyDarkModeIfNeeded(to: webView)

                // Record page load for blocking stats
                if AppSettings.shared.adBlockingEnabled {
                    ContentBlockerManager.shared.recordPageLoad()
                }

                // Record to browsing history with current workspace
                if let url = webView.url {
                    let title = webView.title ?? "Untitled"
                    let workspaceID = WorkspaceManager.shared.currentWorkspaceID
                    BrowsingHistory.shared.addEntry(url: url, title: title, workspaceID: workspaceID)

                    // Index for semantic search (extract content and embed)
                    self.indexPageForSemanticSearch(webView: webView, url: url, title: title, workspaceID: workspaceID)
                }

                // Capture screenshot for tab preview after a short delay
                // to allow page rendering to complete
                let tab = self.tab
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                    await TabScreenshotManager.shared.captureScreenshot(for: tab)
                }
            }
        }

        /// Apply dark mode to the webview based on current settings
        private func applyDarkModeIfNeeded(to webView: WKWebView) {
            let settings = AppSettings.shared
            let shouldEnable: Bool

            switch settings.darkModeMode {
            case .on:
                shouldEnable = true
            case .off:
                shouldEnable = false
            case .auto:
                if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                    shouldEnable = appearance == .darkAqua
                } else {
                    shouldEnable = false
                }
            }

            let script = shouldEnable ? DarkModeScripts.enableScript() : DarkModeScripts.disableScript()
            webView.evaluateJavaScript(script) { _, _ in }
        }

        private func indexPageForSemanticSearch(webView: WKWebView, url: URL, title: String, workspaceID: UUID?) {
            // Check if semantic search is enabled
            guard AppSettings.shared.semanticSearchEnabled else { return }

            // Skip certain URLs
            let urlString = url.absoluteString
            let skipPrefixes = ["about:", "data:", "javascript:", "blob:", "chrome:", "file:"]
            for prefix in skipPrefixes {
                if urlString.hasPrefix(prefix) { return }
            }

            // Check if this is a PDF - we can't extract content via JavaScript
            // but we still want to register it so it can be saved to reading list
            let isPDF = url.pathExtension.lowercased() == "pdf" ||
                        urlString.lowercased().contains(".pdf")

            if isPDF {
                Task { @MainActor in
                    await SemanticSearchManagerV2.shared.registerPage(
                        url: urlString,
                        title: title,
                        workspaceID: workspaceID
                    )
                }
                return
            }

            // Extract content via JavaScript
            let extractionScript = """
            (function() {
                const removeSelectors = [
                    'script', 'style', 'noscript', 'iframe', 'svg',
                    'nav', 'header', 'footer', 'aside',
                    '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
                    '.sidebar', '.nav', '.menu', '.advertisement', '.ad',
                    '.cookie-banner', '.popup', '.modal', '[aria-hidden="true"]'
                ];
                const doc = document.cloneNode(true);
                removeSelectors.forEach(selector => {
                    doc.querySelectorAll(selector).forEach(el => el.remove());
                });
                const mainContent = doc.querySelector('main, article, [role="main"], .content, .post, .article');
                const contentElement = mainContent || doc.body;
                let text = contentElement ? contentElement.innerText : document.body.innerText;
                text = text.replace(/\\s+/g, ' ').replace(/\\n\\s*\\n/g, '\\n').trim();
                return text;
            })();
            """

            webView.evaluateJavaScript(extractionScript) { result, error in
                guard error == nil, let content = result as? String, !content.isEmpty else {
                    return
                }

                // Use the new V2 manager with sqlite-vec backend
                Task { @MainActor in
                    await SemanticSearchManagerV2.shared.indexPage(
                        url: urlString,
                        title: title,
                        content: content,
                        workspaceID: workspaceID
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
        }

        // MARK: - Download Policy Decisions

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            // Check if the navigation action should be a download
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download, preferences)
            } else {
                decisionHandler(.allow, preferences)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard let response = navigationResponse.response as? HTTPURLResponse else {
                decisionHandler(.allow)
                return
            }

            // Only allow downloads for successful responses (2xx status codes)
            // This prevents downloading error pages (404, 403, etc.) as files
            guard (200...299).contains(response.statusCode) else {
                decisionHandler(.allow)
                return
            }

            // Check Content-Disposition header for attachment
            if let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition"),
               contentDisposition.lowercased().contains("attachment") {
                decisionHandler(.download)
                return
            }

            // Check MIME type
            if let mimeType = response.mimeType?.lowercased(),
               downloadableMimeTypes.contains(mimeType) {
                // For PDF, allow inline viewing unless it's explicitly a download
                if mimeType == "application/pdf" && navigationResponse.canShowMIMEType {
                    decisionHandler(.allow)
                    return
                }
                decisionHandler(.download)
                return
            }

            // Check if the response cannot be displayed
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
            currentDownload = download
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
            currentDownload = download
        }

        // MARK: - WKDownloadDelegate

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            downloadFilename = suggestedFilename

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
            destinationURL = getUniqueFileURL(basePath: destinationURL)

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
            // Clean up progress observation
            progressObservations.removeValue(forKey: download)

            Task { @MainActor in
                DownloadManager.shared.completeDownload(download)
            }
            currentDownload = nil
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            // Clean up progress observation
            progressObservations.removeValue(forKey: download)

            Task { @MainActor in
                DownloadManager.shared.failDownload(download, error: error.localizedDescription)
            }
            currentDownload = nil
        }

        private func getUniqueFileURL(basePath: URL) -> URL {
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

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = "Alert"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Confirm"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle popup windows for OAuth flows
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
