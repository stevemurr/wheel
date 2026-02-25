import SwiftUI
import WebKit

/// Manages screenshot capture and caching for tab previews with LRU eviction
@MainActor
class TabScreenshotManager: ObservableObject {
    static let shared = TabScreenshotManager()

    /// Maximum number of screenshots to cache before evicting oldest entries
    private let maxCacheSize = 25

    /// Screenshots stored in a dictionary for O(1) lookup
    @Published private(set) var screenshots: [UUID: NSImage] = [:]

    /// Tracks access order for LRU eviction (most recently used at end)
    private var accessOrder: [UUID] = []

    private let thumbnailSize = CGSize(width: 160, height: 100)

    private init() {}

    /// Captures a screenshot of the given tab's web view and caches it
    func captureScreenshot(for tab: Tab) async {
        let webView = tab.webView

        // Configure snapshot to capture the visible portion
        let config = WKSnapshotConfiguration()

        do {
            let image = try await webView.takeSnapshot(configuration: config)

            // Resize to thumbnail size on background queue to avoid blocking main thread
            let thumbnail = await resizeImageAsync(image, to: thumbnailSize)

            // Update cache with LRU tracking
            cacheScreenshot(thumbnail, for: tab.id)
        } catch {
            // Capture failed - leave existing screenshot or placeholder
            Log.Screenshot.error("Screenshot capture failed for tab \(tab.id): \(error.localizedDescription)")
        }
    }

    /// Caches a screenshot with LRU eviction
    private func cacheScreenshot(_ image: NSImage, for tabId: UUID) {
        // Remove from current position in access order if it exists
        if let index = accessOrder.firstIndex(of: tabId) {
            accessOrder.remove(at: index)
        }

        // Add to end of access order (most recently used)
        accessOrder.append(tabId)

        // Store the screenshot
        screenshots[tabId] = image

        // Evict oldest entries if over capacity
        evictIfNeeded()
    }

    /// Evicts least recently used screenshots if cache exceeds max size
    private func evictIfNeeded() {
        while accessOrder.count > maxCacheSize {
            let oldestTabId = accessOrder.removeFirst()
            screenshots.removeValue(forKey: oldestTabId)
        }
    }

    /// Returns the cached screenshot for a tab, or nil if not available
    /// Also updates LRU access order to mark this screenshot as recently used
    func getScreenshot(for tabId: UUID) -> NSImage? {
        guard let screenshot = screenshots[tabId] else {
            return nil
        }

        // Update access order (move to most recently used position)
        if let index = accessOrder.firstIndex(of: tabId) {
            accessOrder.remove(at: index)
            accessOrder.append(tabId)
        }

        return screenshot
    }

    /// Removes the screenshot for a tab (e.g., when tab is closed)
    func removeScreenshot(for tabId: UUID) {
        screenshots.removeValue(forKey: tabId)
        if let index = accessOrder.firstIndex(of: tabId) {
            accessOrder.remove(at: index)
        }
    }

    /// Resizes an image to the specified size while maintaining aspect ratio (async, runs on background queue)
    private func resizeImageAsync(_ image: NSImage, to targetSize: CGSize) async -> NSImage {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let resized = Self.resizeImageSync(image, to: targetSize)
                continuation.resume(returning: resized)
            }
        }
    }

    /// Resizes an image to the specified size while maintaining aspect ratio (synchronous, for background use)
    /// Note: This is nonisolated to allow calling from background queue
    private nonisolated static func resizeImageSync(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let sourceSize = image.size

        // Calculate aspect-fit size
        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        // Use NSBitmapImageRep for thread-safe image creation
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            NSGraphicsContext.restoreGraphicsState()
            return image
        }
        NSGraphicsContext.current = context

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

        NSGraphicsContext.restoreGraphicsState()

        let newImage = NSImage(size: targetSize)
        newImage.addRepresentation(bitmapRep)
        return newImage
    }
}
