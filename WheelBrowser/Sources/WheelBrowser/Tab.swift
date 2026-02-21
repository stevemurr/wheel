import Foundation
import WebKit
import AppKit

class Tab: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var zoomLevel: Double = 1.0
    @Published var isFindBarVisible: Bool = false
    @Published var findSearchText: String = ""
    @Published var hasActiveAgent: Bool = false
    @Published var agentProgress: String = ""

    let webView: WKWebView

    // Zoom constants
    private let minZoom: Double = 0.5
    private let maxZoom: Double = 3.0
    private let zoomStep: Double = 0.1

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true

        // Enable Picture-in-Picture using KVC (required on macOS, private API)
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")

        // Inject dark mode script at document start to prevent flash of light content
        let darkModeScript = Tab.createDarkModeUserScript()
        config.userContentController.addUserScript(darkModeScript)

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.allowsBackForwardNavigationGestures = true

        // Apply ad blocking rules after webView is created
        if AppSettings.shared.adBlockingEnabled {
            Task { @MainActor in
                await ContentBlockerManager.shared.applyRules(to: self.webView)
            }
        }
    }

    func load(_ urlString: String) {
        var urlToLoad = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https if no scheme provided
        if !urlToLoad.contains("://") {
            // Check if it looks like a URL or a search query
            if urlToLoad.contains(".") && !urlToLoad.contains(" ") {
                urlToLoad = "https://\(urlToLoad)"
            } else {
                // Treat as search query
                let encoded = urlToLoad.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlToLoad
                urlToLoad = "https://duckduckgo.com/?q=\(encoded)"
            }
        }

        if let url = URL(string: urlToLoad) {
            self.url = url
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    // MARK: - Zoom Controls

    func zoomIn() {
        let newZoom = min(zoomLevel + zoomStep, maxZoom)
        setZoom(newZoom)
    }

    func zoomOut() {
        let newZoom = max(zoomLevel - zoomStep, minZoom)
        setZoom(newZoom)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    private func setZoom(_ level: Double) {
        zoomLevel = level
        webView.pageZoom = level
    }

    // MARK: - Find in Page

    func showFindBar() {
        isFindBarVisible = true
    }

    func hideFindBar() {
        isFindBarVisible = false
        findSearchText = ""
        clearFindHighlights()
    }

    func findInPage(_ searchText: String) {
        findSearchText = searchText
        guard !searchText.isEmpty else {
            clearFindHighlights()
            return
        }

        // Use JavaScript to find and highlight text
        let escapedText = searchText.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        (function() {
            // Clear previous highlights
            document.querySelectorAll('.wheel-find-highlight').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });

            const searchText = '\(escapedText)';
            if (!searchText) return { found: 0 };

            const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );

            const nodesToHighlight = [];
            let node;
            while (node = walker.nextNode()) {
                if (node.nodeValue.toLowerCase().includes(searchText.toLowerCase())) {
                    nodesToHighlight.push(node);
                }
            }

            let count = 0;
            nodesToHighlight.forEach(textNode => {
                const text = textNode.nodeValue;
                const regex = new RegExp('(' + searchText.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&') + ')', 'gi');
                const parts = text.split(regex);

                if (parts.length > 1) {
                    const fragment = document.createDocumentFragment();
                    parts.forEach(part => {
                        if (part.toLowerCase() === searchText.toLowerCase()) {
                            const span = document.createElement('span');
                            span.className = 'wheel-find-highlight';
                            span.style.backgroundColor = '#ffff00';
                            span.style.color = '#000000';
                            span.textContent = part;
                            fragment.appendChild(span);
                            count++;
                        } else {
                            fragment.appendChild(document.createTextNode(part));
                        }
                    });
                    textNode.parentNode.replaceChild(fragment, textNode);
                }
            });

            // Scroll to first match
            const firstMatch = document.querySelector('.wheel-find-highlight');
            if (firstMatch) {
                firstMatch.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }

            return { found: count };
        })();
        """

        webView.evaluateJavaScript(script) { _, _ in }
    }

    func findNext() {
        let script = """
        (function() {
            const highlights = document.querySelectorAll('.wheel-find-highlight');
            if (highlights.length === 0) return;

            let currentIndex = -1;
            highlights.forEach((el, i) => {
                if (el.classList.contains('wheel-find-current')) {
                    currentIndex = i;
                    el.classList.remove('wheel-find-current');
                    el.style.backgroundColor = '#ffff00';
                }
            });

            const nextIndex = (currentIndex + 1) % highlights.length;
            const nextEl = highlights[nextIndex];
            nextEl.classList.add('wheel-find-current');
            nextEl.style.backgroundColor = '#ff9500';
            nextEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        })();
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }

    func findPrevious() {
        let script = """
        (function() {
            const highlights = document.querySelectorAll('.wheel-find-highlight');
            if (highlights.length === 0) return;

            let currentIndex = 0;
            highlights.forEach((el, i) => {
                if (el.classList.contains('wheel-find-current')) {
                    currentIndex = i;
                    el.classList.remove('wheel-find-current');
                    el.style.backgroundColor = '#ffff00';
                }
            });

            const prevIndex = (currentIndex - 1 + highlights.length) % highlights.length;
            const prevEl = highlights[prevIndex];
            prevEl.classList.add('wheel-find-current');
            prevEl.style.backgroundColor = '#ff9500';
            prevEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        })();
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }

    private func clearFindHighlights() {
        let script = """
        (function() {
            document.querySelectorAll('.wheel-find-highlight').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });
        })();
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }

    // MARK: - Dark Mode Helper

    /// Creates a dark mode user script based on current settings
    /// This is a static method to avoid MainActor isolation issues during init
    private static func createDarkModeUserScript() -> WKUserScript {
        let settings = AppSettings.shared
        let shouldEnable: Bool

        switch settings.darkModeMode {
        case .on:
            shouldEnable = true
        case .off:
            shouldEnable = false
        case .auto:
            // Check system appearance synchronously
            if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                shouldEnable = appearance == .darkAqua
            } else {
                shouldEnable = false
            }
        }

        let script = DarkModeScripts.generateBundle(
            enabled: shouldEnable,
            brightness: settings.darkModeBrightness,
            contrast: settings.darkModeContrast
        )

        return WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    // MARK: - Screenshot Capture

    /// Captures a screenshot of this tab for preview purposes
    func captureScreenshot() async {
        await TabScreenshotManager.shared.captureScreenshot(for: self)
    }

    // MARK: - Picture in Picture

    func togglePictureInPicture() {
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
        webView.evaluateJavaScript(script) { _, _ in }
    }
}
