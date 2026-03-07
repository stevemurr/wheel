import Foundation

extension FileManager {
    /// Returns the app-specific Application Support directory, creating it if needed.
    /// Falls back to the temporary directory if Application Support is unavailable.
    static var appSupportDirectory: URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fm.temporaryDirectory.appendingPathComponent("WheelBrowser")
        }
        let appDir = appSupport.appendingPathComponent("WheelBrowser")
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }

    static var extensionsDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("Extensions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static var contentBlockerCacheDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("ContentBlockers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
