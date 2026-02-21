import SwiftUI
import WebKit

/// Manages screenshot capture and caching for tab previews
@MainActor
class TabScreenshotManager: ObservableObject {
    static let shared = TabScreenshotManager()

    @Published private(set) var screenshots: [UUID: NSImage] = [:]

    private let thumbnailSize = CGSize(width: 160, height: 100)

    private init() {}

    /// Captures a screenshot of the given tab's web view and caches it
    func captureScreenshot(for tab: Tab) async {
        let webView = tab.webView

        // Configure snapshot to capture the visible portion
        let config = WKSnapshotConfiguration()

        do {
            let image = try await webView.takeSnapshot(configuration: config)

            // Resize to thumbnail size
            let thumbnail = resizeImage(image, to: thumbnailSize)

            screenshots[tab.id] = thumbnail
        } catch {
            // Capture failed - leave existing screenshot or placeholder
            print("Screenshot capture failed for tab \(tab.id): \(error)")
        }
    }

    /// Returns the cached screenshot for a tab, or nil if not available
    func getScreenshot(for tabId: UUID) -> NSImage? {
        return screenshots[tabId]
    }

    /// Invalidates the cached screenshot for a tab (e.g., when navigation starts)
    func invalidateScreenshot(for tabId: UUID) {
        // Keep old screenshot until new one is captured
        // This prevents flickering during navigation
    }

    /// Removes the screenshot for a tab (e.g., when tab is closed)
    func removeScreenshot(for tabId: UUID) {
        screenshots.removeValue(forKey: tabId)
    }

    /// Resizes an image to the specified size while maintaining aspect ratio
    private func resizeImage(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let sourceSize = image.size

        // Calculate aspect-fit size
        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Fill with a background color to handle any gaps
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        // Calculate centered position
        let origin = CGPoint(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2
        )

        // Draw the scaled image
        image.draw(
            in: NSRect(origin: origin, size: scaledSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1.0
        )

        newImage.unlockFocus()

        return newImage
    }

    /// Creates a placeholder image for tabs without screenshots
    func createPlaceholder(for tab: Tab) -> NSImage {
        let size = thumbnailSize
        let image = NSImage(size: size)

        image.lockFocus()

        // Create gradient background based on URL
        let colors: [NSColor]
        if let url = tab.url, let host = url.host {
            // Generate consistent colors based on domain
            let hash = abs(host.hashValue)
            let hue1 = CGFloat(hash % 360) / 360.0
            let hue2 = CGFloat((hash / 360) % 360) / 360.0

            colors = [
                NSColor(hue: hue1, saturation: 0.3, brightness: 0.4, alpha: 1.0),
                NSColor(hue: hue2, saturation: 0.3, brightness: 0.3, alpha: 1.0)
            ]
        } else {
            colors = [
                NSColor.systemGray.withAlphaComponent(0.3),
                NSColor.systemGray.withAlphaComponent(0.2)
            ]
        }

        // Draw gradient
        if let gradient = NSGradient(colors: colors) {
            gradient.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        }

        // Draw icon or initial
        let iconSize: CGFloat = 32
        let iconRect = NSRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )

        if let url = tab.url, let host = url.host {
            // Draw domain initial
            let initial = String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased()
            let font = NSFont.systemFont(ofSize: 20, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.8)
            ]
            let string = NSAttributedString(string: initial, attributes: attributes)
            let stringSize = string.size()
            let stringRect = NSRect(
                x: (size.width - stringSize.width) / 2,
                y: (size.height - stringSize.height) / 2,
                width: stringSize.width,
                height: stringSize.height
            )
            string.draw(in: stringRect)
        } else {
            // Draw globe icon
            if let globeImage = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
                let tintedGlobe = globeImage.withSymbolConfiguration(config)
                tintedGlobe?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.6)
            }
        }

        image.unlockFocus()

        return image
    }
}
