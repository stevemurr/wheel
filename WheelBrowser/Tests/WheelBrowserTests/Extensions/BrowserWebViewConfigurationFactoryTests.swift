import Foundation
import Testing
@testable import WheelBrowser

@Suite("BrowserWebViewConfigurationFactory Tests")
@MainActor
struct BrowserWebViewConfigurationFactoryTests {
    @Test("Tab configs include tab-only built-ins and extension scripts")
    func tabAndOverlayConfigsDifferBySurface() async throws {
        AppSettings.shared.extensionsEnabled = true

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let bundledRoot = tempRoot.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)

        try ExtensionTestSupport.makeLocalExtension(
            in: bundledRoot,
            folderName: "surface-test",
            extensionID: "com.example.surface"
        )

        let blockerManager = ContentBlockerManager(
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )
        let registry = ExtensionRegistry(
            bundledExtensionsURL: bundledRoot,
            sideloadedExtensionsURL: tempRoot.appendingPathComponent("sideloaded", isDirectory: true),
            stateFileURL: tempRoot.appendingPathComponent("extensions.json"),
            contentBlockerManager: blockerManager
        )

        await registry.reload()

        let factory = BrowserWebViewConfigurationFactory(registry: registry)
        let tabConfiguration = factory.makeConfiguration(surface: .tab)
        let overlayConfiguration = factory.makeConfiguration(surface: .overlay)

        #expect(tabConfiguration.userContentController.userScripts.count == overlayConfiguration.userContentController.userScripts.count + 1)
        #expect(overlayConfiguration.userContentController.userScripts.count >= 1)
    }
}
