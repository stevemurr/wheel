import AppKit
import QuartzCore
import WebKit

@MainActor
enum ReaderModeTransitionAnimator {
    static func perform<T>(
        in webView: WKWebView,
        duration: TimeInterval = 0.2,
        operation: @escaping @MainActor () async throws -> T
    ) async rethrows -> T {
        let overlay = await makeSnapshotOverlay(for: webView)
        let result = try await operation()
        await fadeOutAndRemove(overlay, duration: duration)
        return result
    }

    private static func makeSnapshotOverlay(for webView: WKWebView) async -> NSImageView? {
        guard let container = webView.superview,
              webView.bounds.width > 1,
              webView.bounds.height > 1,
              let image = try? await webView.snapshotImage() else {
            return nil
        }

        let overlay = NSImageView(image: image)
        overlay.frame = webView.frame
        overlay.imageScaling = .scaleAxesIndependently
        overlay.autoresizingMask = [.width, .height]
        overlay.alphaValue = 1
        overlay.wantsLayer = true
        overlay.layer?.masksToBounds = true
        overlay.layer?.cornerRadius = webView.layer?.cornerRadius ?? 0
        overlay.layer?.borderWidth = 1
        overlay.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.12).cgColor

        container.addSubview(overlay, positioned: .above, relativeTo: webView)
        return overlay
    }

    private static func fadeOutAndRemove(_ overlay: NSView?, duration: TimeInterval) async {
        guard let overlay else { return }

        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                overlay.animator().alphaValue = 0
            } completionHandler: {
                overlay.removeFromSuperview()
                continuation.resume()
            }
        }
    }
}

private extension WKWebView {
    func snapshotImage() async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = bounds
            takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: SnapshotError.missingImage)
                }
            }
        }
    }

    enum SnapshotError: Error {
        case missingImage
    }
}
