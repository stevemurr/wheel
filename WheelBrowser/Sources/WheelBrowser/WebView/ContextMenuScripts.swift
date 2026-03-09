import Foundation

/// JavaScript hit-test factory for the custom context menu.
///
/// Returns a single IIFE that inspects the element at the given CSS coordinates
/// and returns a JSON object describing what's under the cursor (link, image,
/// media, selection, editable field).
enum ContextMenuScripts {

    /// Build a JS snippet that hit-tests at (`cssX`, `cssY`) and returns a
    /// JSON string with all relevant context menu metadata.
    static func hitTest(cssX: CGFloat, cssY: CGFloat) -> String {
        """
        (function() {
            var result = {
                linkURL: '',
                linkText: '',
                imageSrc: '',
                imageAlt: '',
                mediaSrc: '',
                mediaTagName: '',
                mediaCurrentTime: null,
                selectedText: '',
                isEditable: false,
                pageCanonicalURL: '',
                pageURL: location.href,
                pageTitle: document.title
            };

            try {
                var canonicalLink = document.querySelector('link[rel="canonical"]');
                if (canonicalLink && canonicalLink.href) {
                    result.pageCanonicalURL = canonicalLink.href;
                } else {
                    var ogURL = document.querySelector('meta[property="og:url"], meta[name="og:url"]');
                    if (ogURL && ogURL.content) {
                        result.pageCanonicalURL = ogURL.content;
                    }
                }
            } catch(e) {}

            // Selected text
            var sel = window.getSelection();
            if (sel && sel.toString().length > 0) {
                result.selectedText = sel.toString().substring(0, 500);
            }

            var el = document.elementFromPoint(\(cssX), \(cssY));
            if (!el) return JSON.stringify(result);

            // Editable check
            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable) {
                result.isEditable = true;
            }

            // Image check — direct hit on <img>
            if (el.tagName === 'IMG' && el.src) {
                result.imageSrc = el.src;
                result.imageAlt = el.alt || '';
            }

            // CSS background-image fallback
            if (!result.imageSrc) {
                try {
                    var bg = window.getComputedStyle(el).backgroundImage;
                    if (bg && bg !== 'none') {
                        var m = bg.match(/url\\(["']?(.*?)["']?\\)/);
                        if (m && m[1]) result.imageSrc = m[1];
                    }
                } catch(e) {}
            }

            // Media check — nearest <video> or <audio>
            var mediaEl = el;
            while (mediaEl) {
                if (mediaEl.tagName === 'VIDEO' || mediaEl.tagName === 'AUDIO') {
                    result.mediaSrc = mediaEl.currentSrc || mediaEl.src || '';
                    result.mediaTagName = mediaEl.tagName.toLowerCase();
                    if (typeof mediaEl.currentTime === 'number' && isFinite(mediaEl.currentTime)) {
                        result.mediaCurrentTime = mediaEl.currentTime;
                    }
                    break;
                }
                if (mediaEl.parentElement) {
                    mediaEl = mediaEl.parentElement;
                } else {
                    var mediaRoot = mediaEl.getRootNode();
                    if (mediaRoot && mediaRoot !== document && mediaRoot.host) {
                        mediaEl = mediaRoot.host;
                    } else {
                        break;
                    }
                }
            }

            // Walk up DOM (including shadow DOM) to find nearest <a>
            var walker = el;
            while (walker) {
                if (walker.tagName === 'A' && walker.href) {
                    result.linkURL = walker.href;
                    result.linkText = (walker.textContent || '').trim().substring(0, 200);
                    break;
                }
                if (walker.parentElement) {
                    walker = walker.parentElement;
                } else {
                    var root = walker.getRootNode();
                    if (root && root !== document && root.host) {
                        walker = root.host;
                    } else {
                        break;
                    }
                }
            }

            return JSON.stringify(result);
        })()
        """
    }
}
