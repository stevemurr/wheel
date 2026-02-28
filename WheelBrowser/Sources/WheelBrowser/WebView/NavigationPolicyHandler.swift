import WebKit

/// Handles navigation policy decisions (allow, cancel, download) for WKWebView.
///
/// The Coordinator delegates `decidePolicyFor navigationAction` and
/// `decidePolicyFor navigationResponse` to this handler.
struct NavigationPolicyHandler {

    /// MIME types that should trigger a download rather than inline display.
    let downloadableMimeTypes: Set<String> = [
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

    // MARK: - Navigation Action Policy

    func decidePolicy(
        for navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
    }

    // MARK: - Navigation Response Policy

    func decidePolicy(
        for navigationResponse: WKNavigationResponse,
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
}
