import Foundation
import WebKit

/// Handles Picture-in-Picture toggle via JavaScript on a WKWebView.
class PictureInPictureController {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func toggle() {
        guard let webView = webView else { return }

        let script = """
        (function() {
            // Find the best video candidate (largest visible video that's playing or has content)
            const videos = Array.from(document.querySelectorAll('video'));
            if (videos.length === 0) {
                return { success: false, error: 'No video found on page', videoCount: 0 };
            }

            // Sort by visibility and size, prefer playing videos
            const scoredVideos = videos.map(v => {
                const rect = v.getBoundingClientRect();
                const isVisible = rect.width > 0 && rect.height > 0;
                const size = rect.width * rect.height;
                const isPlaying = !v.paused && !v.ended;
                const hasSource = v.src || v.querySelector('source');
                return { video: v, score: (isVisible ? size : 0) + (isPlaying ? 1000000 : 0) + (hasSource ? 100 : 0) };
            }).sort((a, b) => b.score - a.score);

            const video = scoredVideos[0]?.video;
            if (!video) {
                return { success: false, error: 'No suitable video found' };
            }

            // Try Safari/WebKit native API first (works better programmatically)
            if (typeof video.webkitSetPresentationMode === 'function') {
                const currentMode = video.webkitPresentationMode;
                if (currentMode === 'picture-in-picture') {
                    video.webkitSetPresentationMode('inline');
                    return { success: true, action: 'exit', method: 'webkit' };
                } else {
                    video.webkitSetPresentationMode('picture-in-picture');
                    return { success: true, action: 'enter', method: 'webkit' };
                }
            }

            // Fallback to standard API
            if (document.pictureInPictureElement) {
                document.exitPictureInPicture();
                return { success: true, action: 'exit', method: 'standard' };
            }

            if (!document.pictureInPictureEnabled) {
                return { success: false, error: 'Picture-in-Picture not supported' };
            }

            if (video.disablePictureInPicture) {
                return { success: false, error: 'Picture-in-Picture disabled for this video' };
            }

            video.requestPictureInPicture()
                .then(() => console.log('PiP activated'))
                .catch(err => console.error('PiP error:', err.message));

            return { success: true, action: 'enter', method: 'standard-async' };
        })();
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                Log.Browser.debug("Toggle PiP JS failed: \(error.localizedDescription)")
            }
        }
    }
}
